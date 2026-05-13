`timescale 1ns / 1ps

interface uart_tx_interface;
    logic       rst;
    logic       rx;
    logic       b_tick;
    logic       rx_done;
    logic [7:0] rx_data;

    parameter BIT_PERIOD = 100_000_000 / 9600;
endinterface

class transaction;
    //generator: 랜텀 8비트 데이터 생성. -> 8bit -> driver
    //driver: 1bit -> dut
    //dut: rx핀을 다시 8비트로 조립. 조립이 끝나면 rx_done=1, rx_data 8비트를 내보냄.
    //monitor: rx_done==1이 되는 순간 rx_data를 scoreboard로 전달.
    //scb: generator값과 monitor값을 비교해서 pass fail.
    bit            rst;
    bit            rx;
    bit            b_tick;
    bit            rx_done;
    rand bit [7:0] rx_data;

    //디버깅용 display 함수
    function debug_print(string name);
        $display("[%s] : rx_data = %d, rx_done = %d", name, rx_data, rx_done);
    endfunction
endclass

class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    event event_gen_next;
    function new(mailbox#(transaction) gen2drv_mbox, event event_gen_next);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.event_gen_next = event_gen_next;
    endfunction
    task run(int count);
        repeat (count) begin
            tr = new;
            tr.randomize();
            gen2drv_mbox.put(tr);
            tr.debug_print("GEN");
            @(event_gen_next);
        end
    endtask
endclass

class driver #(
    parameter BIT_PERIOD
);
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual uart_rx_interface uart_vif;
    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual uart_rx_interface uart_vif);
        this.gen2drv_mbox = gen2drv_mbox;
        this.uart_vif     = uart_vif;
    endfunction
    task run();
        forever begin
            gen2drv_mbox.get(tr);
            tr.debug_print("DRV");
            //start bit
            uart_vif.rx = 0;
            #(BIT_PERIOD);
            //data bit
            for (int i = 0; i < 8; i++) begin
                uart_vif.rx = tr.rx_data[i];
                #(BIT_PERIOD);
            end
            //stop bit
            uart_vif.rx = 1;
        end
    endtask
endclass

class monitor;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    virtual uart_rx_interface uart_vif;
    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual uart_rx_interface uart_vif);
        this.mon2scb_mbox = mon2scb_mbox;
        this.uart_vif     = uart_vif;
    endfunction
    task run();
        forever begin
            tr = new;
            @(negedge uart_vif.rx_done);
            tr.rx_data = uart_vif.rx_data;
            tr.rx_done = uart_vif.rx_done;
            mon2drv_mbox.put(tr);
            $display("MON");
        end
    endtask
endclass

class scoreboard;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event event_gen_next;
    function new(mailbox#(transaction) mon2scb_mbox, event event_gen_next);
        this.mon2scb_mbox   = mon2scb_mbox;
        this.event_gen_next = event_gen_next;
    endfunction
    task run();
        forever begin
            mon2scb_mbox.get(tr);
            $display("SCB");
            ->event_gen_next;
        end
    endtask
endclass


module tb_uart_rx_sv ();  //tb_uart_sv

    uart_rx_sv dut (
        .clk(),
        .rst(),
        .rx(),
        .b_tick(),
        .rx_done(),
        .rx_data()
    );

endmodule

