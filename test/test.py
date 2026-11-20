# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# Tabla de referencia para decodificar segmentos {g,f,e,d,c,b,a} -> entero
SEG_TO_DIGIT = {
    0b0111111: 0,
    0b0000110: 1,
    0b1011011: 2,
    0b1001111: 3,
    0b1100110: 4,
    0b1101101: 5,
    0b1111101: 6,
    0b0000111: 7,
    0b1111111: 8,
    0b1101111: 9,
}

async def simular_incremento(dut):
    """Simula un cruce completo: sensor_ext (Set) -> sensor_int (Reset)"""
    dut.ui_in.value = 0b01  # sensor_ext = 1, sensor_int = 0
    await ClockCycles(dut.clk, 5)
    dut.ui_in.value = 0b11  # Ambos activos
    await ClockCycles(dut.clk, 5)
    dut.ui_in.value = 0b10  # sensor_ext = 0, sensor_int = 1
    await ClockCycles(dut.clk, 5)
    dut.ui_in.value = 0b00  # Ambos libres -> Ejecuta +1
    await ClockCycles(dut.clk, 5)

async def simular_decremento(dut):
    """Simula un cruce inverso: sensor_int (Set) -> sensor_ext (Reset)"""
    dut.ui_in.value = 0b10  # sensor_int = 1, sensor_ext = 0
    await ClockCycles(dut.clk, 5)
    dut.ui_in.value = 0b11  # Ambos activos
    await ClockCycles(dut.clk, 5)
    dut.ui_in.value = 0b01  # sensor_int = 0, sensor_ext = 1
    await ClockCycles(dut.clk, 5)
    dut.ui_in.value = 0b00  # Ambos libres -> Ejecuta -1
    await ClockCycles(dut.clk, 5)

async def leer_displays_multiplexados(dut):
    """Escanea los 3 displays multiplexados durante un ciclo completo (~30,005 ciclos)"""
    digitos = {0: None, 1: None, 2: None}

    # Escaneamos en pasos de 2,500 ciclos para capturar cada ventana de 10,000 ciclos
    for _ in range(14):
        await ClockCycles(dut.clk, 2500)
        sel = int(dut.uio_out.value) & 0b111
        seg = int(dut.uo_out.value) & 0b01111111

        assert seg in SEG_TO_DIGIT, f"Patron de segmentos invalido: {bin(seg)}"
        valor = SEG_TO_DIGIT[seg]

        if sel == 0b001:    # Display 0: Unidades
            digitos[0] = valor
        elif sel == 0b010:  # Display 1: Decenas
            digitos[1] = valor
        elif sel == 0b100:  # Display 2: Centenas
            digitos[2] = valor
        else:
            assert False, f"Seleccion de digito invalida en uio_out[2:0]: {bin(sel)}"

    assert None not in digitos.values(), f"No se multiplexaron los 3 digitos: {digitos}"
    return digitos[2] * 100 + digitos[1] * 10 + digitos[0]

@cocotb.test()
async def test_contador_sensores_y_displays(dut):
    dut._log.info("Iniciando simulacion a 10 MHz (100 ns periodo)")

    # 1. Arrancar reloj de 10 MHz (100 ns)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    # 2. Secuencia de Reset inicial
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    # Verificar que uio_oe habilite solo los 3 pines de seleccion (0b00000111)
    assert int(dut.uio_oe.value) == 0b00000111, f"uio_oe inesperado: {bin(int(dut.uio_oe.value))}"

    # 3. Verificar conteo inicial en 000 a traves de los displays
    cuenta_leida = await leer_displays_multiplexados(dut)
    assert cuenta_leida == 0, f"Se esperaba 000, se leyo {cuenta_leida:03d}"
    dut._log.info("Display verificado en 000")

    # 4. Probar 12 incrementos consecutivos (debe mostrar 012)
    for _ in range(12):
        await simular_incremento(dut)

    cuenta_leida = await leer_displays_multiplexados(dut)
    assert cuenta_leida == 12, f"Se esperaba 012, se leyo {cuenta_leida:03d}"
    dut._log.info("Display verificado en 012 tras 12 incrementos")

    # 5. Probar falso disparo (activa sensor_ext y retrocede sin tocar sensor_int)
    dut.ui_in.value = 0b01
    await ClockCycles(dut.clk, 5)
    dut.ui_in.value = 0b00
    await ClockCycles(dut.clk, 5)

    cuenta_leida = await leer_displays_multiplexados(dut)
    assert cuenta_leida == 12, f"El falso disparo altero la cuenta: {cuenta_leida:03d}"
    dut._log.info("Falso disparo rechazado correctamente (mantiene 012)")

    # 6. Probar 3 decrementos consecutivos (12 - 3 = 009)
    for _ in range(3):
        await simular_decremento(dut)

    cuenta_leida = await leer_displays_multiplexados(dut)
    assert cuenta_leida == 9, f"Se esperaba 009, se leyo {cuenta_leida:03d}"
    dut._log.info("Display verificado en 009 tras 3 decrementos")

    # one or more clock cycles, and asserting the expected output values.
