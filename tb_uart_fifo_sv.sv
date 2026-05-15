`timescale 1ns / 1ps
`define BIT_PERIOD (100_000_000/9600)*10

interface uart_fifo_interface;
    logic clk;
    logic rst;
    logic rx;
    logic tx;
endinterface

class transaction;
    rand bit [7:0] rx_data;
    bit      [7:0] tx_data;
    bit            rst;
    bit            rx;
    bit            tx;
    bit            b_tick;
    bit            rx_done;
    bit            tx_busy;

    //constraint addr_range {addr < 10;}

    function debug_print(string name);
        $display(
            "%t : [%s] rx = %d, tx = %d, rx_done = %d, tx_busy = %d, rx_data = %d, tx_data = %d",
            $time, name, rx, tx, rx_done, tx_busy, rx_data, tx_data);
    endfunction
endclass

class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event event_gen_next;
    function new(mailbox#(transaction) gen2drv_mbox,
                 mailbox#(transaction) gen2scb_mbox, event event_gen_next);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.gen2scb_mbox   = gen2scb_mbox;
        this.event_gen_next = event_gen_next;
    endfunction
    task run(int count);
        repeat (count) begin  // for fork join_any
            tr = new;

            // assertion
            assert (tr.randomize())  // 발생하지 않으면
            else $error("[GEN] tr.randomize() error!");

            gen2drv_mbox.put(tr);
            gen2scb_mbox.put(tr);
            tr.debug_print("GEN");
            @(event_gen_next);
        end
    endtask
endclass

class driver;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual uart_fifo_interface uart_fifo_vif;
    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual uart_fifo_interface uart_fifo_vif);
        this.gen2drv_mbox  = gen2drv_mbox;
        this.uart_fifo_vif = uart_fifo_vif;
    endfunction

    task preset();
        uart_fifo_vif.rst = 1;
        uart_fifo_vif.rx  = 1;  // idle
        repeat (2) @(posedge uart_fifo_vif.clk);
        uart_fifo_vif.rst = 0;
        @(negedge uart_fifo_vif.clk);
    endtask

    task run();
        forever begin
            gen2drv_mbox.get(tr);
            tr.debug_print("DRV");

            // start bit
            uart_fifo_vif.rx = 0;
            #(`BIT_PERIOD / 2);  //8
            //data bit
            for (int i = 0; i < 8; i++) begin
                tr.rx = tr.rx_data[i];
                #(`BIT_PERIOD);  //16
            end
            uart_fifo_vif.rx = 1;
            #(`BIT_PERIOD * 1.5);  //24
        end
    endtask
endclass

class monitor;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    virtual uart_fifo_interface uart_fifo_vif;
    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual uart_fifo_interface uart_fifo_vif);
        this.mon2scb_mbox  = mon2scb_mbox;
        this.uart_fifo_vif = uart_fifo_vif;
    endfunction
    task run();
        forever begin
            @(negedge uart_fifo_vif.tx);
            //tr.rx = uart_fifo_vif.rx;
            //tr.tx = uart_fifo_vif.tx;
            //#1;  // 시뮬레이터 상에서 값이 반영되도록 wait. 시뮬레이터는 상승엣지 이후에 반영.
            //tr = new;
            #(`BIT_PERIOD);  //16
            for (int i = 0; i < 8; i++) begin
                tr.tx_data[i] = uart_fifo_vif.tx;
                #(`BIT_PERIOD);  //16
            end
            #(`BIT_PERIOD);  //16
            tr.debug_print("MON");
            mon2scb_mbox.put(tr);
        end
    endtask
endclass

class scoreboard;
    transaction tr_exp;
    transaction tr_act;
    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event event_gen_next;
    int total_cnt = 0, pass_cnt = 0, fail_cnt = 0;

    //byte mem[256];  //byte니까 2상태

    function new(mailbox#(transaction) mon2scb_mbox,
                 mailbox#(transaction) gen2scb_mbox, event event_gen_next);
        this.mon2scb_mbox   = mon2scb_mbox;
        this.gen2scb_mbox   = gen2scb_mbox;
        this.event_gen_next = event_gen_next;
    endfunction
    task run();
        forever begin
            gen2scb_mbox.get(tr_exp);
            mon2scb_mbox.get(tr_act);
            total_cnt++;
            if (tr_exp.rx_data == tr_act.tx_data) begin
                pass_cnt++;
                $display("[Data Compare] PASS");
            end else begin
                fail_cnt++;
                $display("%t [Data Compare] FAIL : rx_data = %d, tx_data = %d",
                         $time, tr_exp.rx_data, tr_act.tx_data);
            end
            ->event_gen_next;
        end
    endtask
endclass

class environment;
    generator                   gen;
    driver                      drv;
    monitor                     mon;
    scoreboard                  scb;
    mailbox #(transaction)      gen2drv_mbox;
    mailbox #(transaction)      gen2scb_mbox;
    mailbox #(transaction)      mon2scb_mbox;
    virtual uart_fifo_interface uart_fifo_vif;
    event                       event_gen_next;
    function new(virtual uart_fifo_interface uart_fifo_vif);
        gen2drv_mbox = new;
        gen2scb_mbox = new;
        mon2scb_mbox = new;
        gen = new(gen2drv_mbox, gen2scb_mbox, event_gen_next);
        drv = new(gen2drv_mbox, uart_fifo_vif);
        mon = new(mon2scb_mbox, uart_fifo_vif);
        scb = new(mon2scb_mbox, gen2scb_mbox, event_gen_next);
    endfunction
    task run();
        //ram interface initial
        drv.preset();
        fork
            gen.run(20);
            drv.run();
            mon.run();
            scb.run();
        join_any
        #10;
        $display("env run task end");
        $display("__________________________");
        $display("** SRAM IP Verification **");
        $display("**** TOTAL test num = %2d **", scb.total_cnt);
        $display("**** PASS test num = %2d **", scb.pass_cnt);
        $display("**** FAIL test num = %2d **", scb.fail_cnt);
        $display("__________________________");
        $stop;
    endtask
endclass


module tb_uart_fifo_sv ();
    uart_fifo_interface uart_fifo_if ();
    environment env;
    uart_fifo_sv dut (
        .clk(uart_fifo_if.clk),
        .rst(uart_fifo_if.rst),
        .rx (uart_fifo_if.rx),
        .tx (uart_fifo_if.tx)
    );
    always #5 uart_fifo_if.clk = ~uart_fifo_if.clk;

    initial begin
        uart_fifo_if.clk = 0;
        env = new(uart_fifo_if);
        env.run();
    end
endmodule
