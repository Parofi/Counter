`default_nettype none

module tt_um_Parofi_contador_sensores (
    input  wire [7:0] ui_in,    // Entradas dedicadas (Sensores)
    output wire [7:0] uo_out,   // Salidas dedicadas (Segmentos a-g + dp)
    input  wire [7:0] uio_in,   // IOs bidireccionales: Entrada (sin usar)
    output wire [7:0] uio_out,  // IOs bidireccionales: Selección de dígito multiplexado
    output wire [7:0] uio_oe,   // IOs bidireccionales: Habilitación de salida
    input  wire       ena,      // Habilitación del diseño
    input  wire       clk,      // Reloj del sistema (ej. 10 MHz en Tiny Tapeout)
    input  wire       rst_n     // Reset maestro (activo en bajo)
);

    // =========================================================================
    // 1. ENTRADAS Y SINCRONIZACIÓN DE SENSORES
    // =========================================================================
    wire sensor_ext = ui_in[0]; // Sensor Exterior en ui_in[0]
    wire sensor_int = ui_in[1]; // Sensor Interior en ui_in[1]


    reg [1:0] sync_ext, sync_int;
    
    wire ext_limpio = sync_ext[1];
    wire int_limpio = sync_int[1];

    always @(posedge clk) begin
        if (!rst_n) begin
            sync_ext <= 2'b00;
            sync_int <= 2'b00;
        end else begin
            sync_ext <= {sync_ext[0], sensor_ext};
            sync_int <= {sync_int[0], sensor_int};
        end
    end

    // =========================================================================
    // 2. MÁQUINA DE ESTADOS DE PASO BIDIRECCIONAL (SET / RESET)
    // =========================================================================
    localparam [2:0] IDLE      = 3'd0,
                     INC_SET   = 3'd1,
                     INC_CRUCE = 3'd2,
                     DEC_SET   = 3'd3,
                     DEC_CRUCE = 3'd4;

    reg [2:0] estado;
    reg [7:0] cuenta;

    always @(posedge clk) begin
        if (!rst_n) begin
            estado <= IDLE;
            cuenta <= 8'd0;
        end else begin
            case (estado)
                IDLE: begin
                    if (ext_limpio && !int_limpio)
                        estado <= INC_SET;
                    else if (int_limpio && !ext_limpio)
                        estado <= DEC_SET;
                end

                // Secuencia de incremento (sensor_ext = Set, sensor_int = Reset)
                INC_SET: begin
                    if (int_limpio)
                        estado <= INC_CRUCE;
                    else if (!ext_limpio)
                        estado <= IDLE;
                end

                INC_CRUCE: begin
                    if (!ext_limpio && !int_limpio) begin
                        if (cuenta < 8'd255)
                            cuenta <= cuenta + 8'd1;
                        estado <= IDLE;
                    end else if (ext_limpio && !int_limpio) begin
                        estado <= INC_SET;
                    end
                end

                // Secuencia de decremento (sensor_int = Set, sensor_ext = Reset)
                DEC_SET: begin
                    if (ext_limpio)
                        estado <= DEC_CRUCE;
                    else if (!int_limpio)
                        estado <= IDLE;
                end

                DEC_CRUCE: begin
                    if (!ext_limpio && !int_limpio) begin
                        if (cuenta > 8'd0)
                            cuenta <= cuenta - 8'd1;
                        estado <= IDLE;
                    end else if (int_limpio && !ext_limpio) begin
                        estado <= DEC_SET;
                    end
                end

                default: estado <= IDLE;
            endcase
        end
    end

    // =========================================================================
    // 3. CONVERSIÓN BINARIO A BCD (CENTENAS, DECENAS, UNIDADES)
    // =========================================================================
    // División entera optimizada para 8 bits (0 a 255) sin gastar área excesiva en silicio
    wire [3:0] centenas = cuenta / 8'd100;
    wire [7:0] resto    = cuenta % 8'd100;
    wire [3:0] decenas  = resto / 8'd10;
    wire [3:0] unidades = resto % 8'd10;

    // =========================================================================
    // 4. CONTROL DE MULTIPLEXADO DE 3 DISPLAYS
    // =========================================================================
    // Divisor de frecuencia para barrido visual sin parpadeo (~300 Hz por dígito a 10 MHz)
    reg [14:0] mux_timer;
    reg [1:0]  digito_actual;

    always @(posedge clk) begin
        if (!rst_n) begin
            mux_timer     <= 15'd0;
            digito_actual <= 2'd0;
        end else begin
            if (mux_timer == 15'd10000) begin
                mux_timer <= 15'd0;
                if (digito_actual == 2'd2)
                    digito_actual <= 2'd0;
                else
                    digito_actual <= digito_actual + 2'd1;
            end else begin
                mux_timer <= mux_timer + 15'd1;
            end
        end
    end

    // Selección del valor BCD y habilitación del display activo
    reg [3:0] bcd_activo;
    reg [2:0] dig_sel;

    always @(*) begin
        case (digito_actual)
            2'd0: begin
                bcd_activo = unidades;
                dig_sel    = 3'b001; // Activa Display 0 (Unidades)
            end
            2'd1: begin
                bcd_activo = decenas;
                dig_sel    = 3'b010; // Activa Display 1 (Decenas)
            end
            2'd2: begin
                bcd_activo = centenas;
                dig_sel    = 3'b100; // Activa Display 2 (Centenas)
            end
            default: begin
                bcd_activo = 4'd0;
                dig_sel    = 3'b000;
            end
        endcase
    end

    // =========================================================================
    // 5. DECODIFICADOR BCD A 7 SEGMENTOS (Estándar Tiny Tapeout: {g,f,e,d,c,b,a})
    // =========================================================================
    reg [6:0] seg;

    always @(*) begin
        case (bcd_activo)
            4'd0: seg = 7'b0111111; // 0
            4'd1: seg = 7'b0000110; // 1
            4'd2: seg = 7'b1011011; // 2
            4'd3: seg = 7'b1001111; // 3
            4'd4: seg = 7'b1100110; // 4
            4'd5: seg = 7'b1101101; // 5
            4'd6: seg = 7'b1111101; // 6
            4'd7: seg = 7'b0000111; // 7
            4'd8: seg = 7'b1111111; // 8
            4'd9: seg = 7'b1101111; // 9
            default: seg = 7'b0000000;
        endcase
    end

    // =========================================================================
    // 6. ASIGNACIÓN DE SALIDAS Y LIMPIEZA PARA OPENLANE / VERILATOR
    // =========================================================================
    assign uo_out  = {1'b0, seg};        // uo_out[6:0] = segmentos, uo_out = dp apagado
    assign uio_out = {5'b0, dig_sel};    // uio_out[2:0] = selección de dígito
    assign uio_oe  = 8'b0000_0111;       // Habilita uio[2:0] como salidas; uio[7:3] como entradas

    wire _unused = &{ena, ui_in[7:2], uio_in, 1'b0};

endmodule

