`timescale 1ns / 1ps

module uart_sv (  // loopback: rx->tx
    input  logic clk,
    input  logic rst,
    input  logic rx,
    output logic tx
);

    logic b_tick, tx_start;
    logic [7:0] rx_data;

    uart_rx_sv U_UART_RX_SV (
        .*,  //clk, rst, rx, b_tick
        .rx_done(tx_start)
    );

    uart_tx_sv U_UART_TX_SV (
        .*,  //clk, rst, tx, b_tick
        .tx_start(tx_start),
        .tx_data (rx_data),
        .tx_busy ()
    );

    b_tick_gen U_TICK_GEN (
        .*  //clk, rst, b_tick
    );

endmodule

module uart_rx_sv (
    input logic clk,
    input logic rst,
    input logic rx,
    input logic b_tick,
    output logic rx_done,
    output logic [7:0] rx_data
);

    parameter IDLE = 0, START = 1, DATA = 2, STOP = 3;
    logic [1:0] c_state, n_state;
    logic [4:0] b_tick_cnt_reg, b_tick_cnt_next;
    logic [2:0] bit_cnt_reg, bit_cnt_next;
    logic [7:0] data_reg, data_next;

    assign rx_data = data_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            b_tick_cnt_reg <= 0;
            bit_cnt_reg    <= 0;
            data_reg       <= 0;
            c_state        <= IDLE;
        end else begin
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg    <= bit_cnt_next;
            data_reg       <= data_next;
            c_state        <= n_state;
        end
    end

    always_comb begin
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next    = bit_cnt_reg;
        data_next       = data_reg;
        n_state         = c_state;
        rx_done         = 0;
        case (c_state)
            IDLE: begin
                if (!rx) begin
                    b_tick_cnt_next = 0;
                    n_state = START;
                end
            end
            START: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 7) begin
                        b_tick_cnt_next = 0;
                        bit_cnt_next = 0;
                        n_state = DATA;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            DATA: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        data_next[bit_cnt_reg] = rx;
                        if (bit_cnt_reg == 7) begin
                            b_tick_cnt_next = 0;
                            n_state = STOP;
                        end else begin
                            b_tick_cnt_next = 0;
                            bit_cnt_next = bit_cnt_reg + 1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            STOP: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 23) begin
                        rx_done = 1;
                        n_state = IDLE;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            default: n_state = IDLE;
        endcase
    end
endmodule


module uart_tx_sv (
    input logic clk,
    input logic rst,
    input logic tx_start,
    input logic b_tick,
    input logic [7:0] tx_data,
    output logic tx_busy,
    output logic tx
);

    parameter IDLE = 0, START = 1, DATA = 2, STOP = 3;
    logic [1:0] c_state, n_state;
    logic [3:0] b_tick_cnt_reg, b_tick_cnt_next;
    logic [2:0] bit_cnt_reg, bit_cnt_next;
    logic [7:0] data_reg, data_next;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            b_tick_cnt_reg <= 0;
            bit_cnt_reg    <= 0;
            data_reg       <= 0;
            c_state        <= IDLE;
        end else begin
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg    <= bit_cnt_next;
            data_reg       <= data_next;
            c_state        <= n_state;
        end
    end

    always_comb begin
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next    = bit_cnt_reg;
        data_next       = data_reg;
        n_state         = c_state;
        tx_busy         = 1;
        case (c_state)
            IDLE: begin
                tx = 1;
                tx_busy = 0;
                if (tx_start) begin
                    data_next = tx_data;
                    n_state   = START;
                end
            end
            START: begin
                tx = 0;  // start bit
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 0;
                        bit_cnt_next    = 0;
                        n_state         = DATA;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            DATA: begin
                tx = data_reg[bit_cnt_reg];
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        if (bit_cnt_reg == 7) begin
                            b_tick_cnt_next = 0;
                            n_state = STOP;
                        end else begin
                            b_tick_cnt_next = 0;
                            bit_cnt_next = bit_cnt_reg + 1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            STOP: begin
                tx = 1;  // stop bit
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        n_state = IDLE;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            default: n_state = IDLE;
        endcase
    end

endmodule

module b_tick_gen (
    input  logic clk,
    input  logic rst,
    output logic b_tick
);

    parameter F_COUNT = 100_000_000 / (9600 * 16);
    parameter WIDTH = $clog2(F_COUNT) - 1;
    reg [WIDTH:0] counter_reg;


    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            b_tick      <= 0;  //FF
            counter_reg <= 0;
        end else begin
            counter_reg <= counter_reg + 1;
            if (counter_reg == F_COUNT - 1) begin
                b_tick      <= 1;
                counter_reg <= 0;
            end else begin
                b_tick <= 0;
            end
        end
    end
endmodule
