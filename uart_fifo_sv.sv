`timescale 1ns / 1ps

module uart_fifo_sv (
    input  logic clk,
    input  logic rst,
    input  logic rx,
    output logic tx
);
    logic b_tick, rx_done, tx_busy, full, empty;
    logic [7:0] push_data, pop_data;

    uart_rx_sv U_UART_RX (
        .clk    (clk),
        .rst    (rst),
        .rx     (rx),
        .b_tick (b_tick),
        .rx_done(rx_done),
        .rx_data(push_data)
    );

    fifo_sv U_FIFO (
        .clk      (clk),
        .rst      (rst),
        .push     (rx_done & (!full)),
        .pop      ((!tx_busy) & (!empty)),
        .push_data(push_data),
        .pop_data (pop_data),
        .full     (full),
        .empty    (empty)
    );

    uart_tx_sv U_UART_TX (
        .clk     (clk),
        .rst     (rst),
        .tx_start(!empty),
        .b_tick  (b_tick),
        .tx_data (pop_data),
        .tx_busy (tx_busy),
        .tx      (tx)
    );
    b_tick_gen U_B_TICK_GEN (
        .clk   (clk),
        .rst   (rst),
        .b_tick(b_tick)
    );
endmodule

module uart_rx_sv (
    input  logic       clk,
    input  logic       rst,
    input  logic       rx,
    input  logic       b_tick,
    output logic       rx_done,
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
    input  logic       clk,
    input  logic       rst,
    input  logic       tx_start,
    input  logic       b_tick,
    input  logic [7:0] tx_data,
    output logic       tx_busy,
    output logic       tx
);

    parameter IDLE = 0, START = 1, DATA = 2, STOP = 3;
    logic [1:0] c_state, n_state;
    logic [3:0] b_tick_cnt_reg, b_tick_cnt_next;
    logic [2:0] bit_cnt_reg, bit_cnt_next;
    logic [7:0] data_reg, data_next;
    logic tx_reg, tx_next;
    assign tx = tx_reg;


    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            b_tick_cnt_reg <= 0;
            bit_cnt_reg    <= 0;
            data_reg       <= 0;
            c_state        <= IDLE;
            tx_reg         <= 1;
        end else begin
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg    <= bit_cnt_next;
            data_reg       <= data_next;
            c_state        <= n_state;
            tx_reg         <= tx_next;
        end
    end

    always_comb begin
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next    = bit_cnt_reg;
        data_next       = data_reg;
        n_state         = c_state;
        tx_busy         = 1;
        tx_next         = tx_reg;
        case (c_state)
            IDLE: begin
                tx_next = 1;
                tx_busy = 0;
                if (tx_start) begin
                    b_tick_cnt_next = 0;
                    data_next       = tx_data;
                    n_state         = START;
                end
            end
            START: begin
                tx_next = 0;  // start bit
                tx_busy = 1;
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
                tx_next = data_reg[bit_cnt_reg];
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 0;
                        if (bit_cnt_reg == 7) begin
                            bit_cnt_next = 0;
                            n_state = STOP;
                        end else begin
                            bit_cnt_next = bit_cnt_reg + 1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            STOP: begin
                tx_next = 1;  // stop bit
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

module fifo_sv (
    input  logic       clk,
    input  logic       rst,
    input  logic       push,
    input  logic       pop,
    input  logic [7:0] push_data,
    output logic [7:0] pop_data,
    output logic       full,
    output logic       empty
);

    logic [3:0] wptr, rptr;

    control_unit U_CNT_UNIT (  //instance
        .*,
        .wptr(wptr),
        .rptr(rptr)
    );

    reg_file U_REG_FILE (
        .*,
        .wdata(push_data),
        .waddr(wptr),
        .raddr(rptr),
        .we   (push & (~full)),
        .rdata(pop_data)
    );

endmodule

module control_unit (
    input  logic       clk,
    input  logic       rst,
    input  logic       push,
    input  logic       pop,
    output logic       full,
    output logic       empty,
    output logic [3:0] wptr,
    output logic [3:0] rptr
);
    logic full_reg, full_next;
    logic empty_reg, empty_next;
    logic [3:0] wptr_reg, wptr_next;
    logic [3:0] rptr_reg, rptr_next;

    assign wptr  = wptr_reg;
    assign rptr  = rptr_reg;
    assign full  = full_reg;
    assign empty = empty_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            full_reg  <= 0;
            empty_reg <= 1;
            wptr_reg  <= 0;
            rptr_reg  <= 0;
        end else begin
            full_reg  <= full_next;
            empty_reg <= empty_next;
            wptr_reg  <= wptr_next;
            rptr_reg  <= rptr_next;
        end
    end

    always_comb begin
        full_next  = full_reg;
        empty_next = empty_reg;
        wptr_next  = wptr_reg;
        rptr_next  = rptr_reg;
        case ({
            push, pop
        })
            2'b10: begin  // push only
                if (!full_reg) begin
                    wptr_next  = wptr_reg + 1;
                    empty_next = 0;
                    if (wptr_next == rptr_reg) full_next = 1;
                end
            end
            2'b01: begin  // pop only
                if (!empty_reg) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 0;
                    if (rptr_next == wptr_reg) empty_next = 1;
                end
            end
            2'b11: begin
                if (full_reg) begin  // pop
                    rptr_next = rptr_reg + 1;
                    full_next = 0;
                end else if (empty_reg) begin  // push
                    wptr_next  = wptr_reg + 1;
                    empty_next = 0;
                end else begin
                    wptr_next = wptr_reg + 1;
                    rptr_next = rptr_reg + 1;
                end
            end
        endcase
    end
endmodule

module reg_file (
    input  logic       clk,
    input  logic [7:0] wdata,
    input  logic [3:0] waddr,
    input  logic [3:0] raddr,
    input  logic       we,
    output logic [7:0] rdata
);

    logic [7:0] reg_file[0:15];  //4bit

    always_ff @(posedge clk) begin
        if (we) begin
            reg_file[waddr] <= wdata;
        end
    end

    assign rdata = reg_file[raddr]; // pop은 we의 조건x, pop신호가 아니라 raddr가 바뀌면 rdata 변하게끔.

endmodule
