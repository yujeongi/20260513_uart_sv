`timescale 1ns / 1ps
`define BIT_PERIOD (100_000_000/9600)*10


class transaction;
    rand bit [7:0] tx_data;
    bit      [7:0] rx_data;
    bit            rst;
    bit            rx;
    bit            tx;
    //bit            b_tick;
    //bit            rx_done;
    //bit            tx_busy;
    //bit            tx_start;

    //constraint addr_range {addr < 10;}

    function debug_print(string name);
        $display("%t : [%s] rx = %d, tx = %d, rx_data = %d, tx_data = %d",
                 $time, name, rx, tx, rx_data, tx_data);
    endfunction
endclass

interface uart_fifo_interface;
    logic clk;
    logic rst;
    logic rx;
    logic tx;
endinterface

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
            tr.randomize();
            #1;
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
        uart_fifo_vif.rx  = 1;  // 초기값
        repeat (2) @(posedge uart_fifo_vif.clk);
        uart_fifo_vif.rst = 0;
        @(negedge uart_fifo_vif.clk);
    endtask

    task run();  // uart tx
        forever begin
            tr = new;
            gen2drv_mbox.get(tr);
            uart_fifo_vif.rx = 0;  // start bit
            $display("%t start timing", $time);
            #(`BIT_PERIOD);  //16, idle->start
            for (int i = 0; i < 8; i++) begin
                $display("%t drive timing", $time);
                uart_fifo_vif.rx = tr.tx_data[i];  // 쪼개주기
                #(`BIT_PERIOD);  //16, start->data
            end
            tr.debug_print("DRV");
            uart_fifo_vif.rx = 1;  //stop bit
            #(`BIT_PERIOD);  //16, data->stop
            $display("%t stop timing", $time);
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
            #1;
            tr = new;
            // start bit
            #(`BIT_PERIOD / 2);  //8, start->data
            //data bit
            for (int i = 0; i < 8; i++) begin
                $display("%t monitoring timing", $time);
                tr.rx_data[i] = uart_fifo_vif.tx;
                #(`BIT_PERIOD);  //16
            end
            tr.debug_print("MON");
            mon2scb_mbox.put(tr);
            #(`BIT_PERIOD);  //24?
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
            if (tr_exp.tx_data == tr_act.rx_data) begin
                pass_cnt++;
                $display(
                    "%t [Data Compare] PASS : EXP_DATA = %d, ACT_DATA = %d",
                    $time, tr_exp.tx_data, tr_act.rx_data);
            end else begin
                fail_cnt++;
                $display(
                    "%t [Data Compare] FAIL : EXP_DATA = %d, ACT_DATA = %d",
                    $time, tr_exp.tx_data, tr_act.rx_data);
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
        gen          = new(gen2drv_mbox, gen2scb_mbox, event_gen_next);
        drv          = new(gen2drv_mbox, uart_fifo_vif);
        mon          = new(mon2scb_mbox, uart_fifo_vif);
        scb          = new(mon2scb_mbox, gen2scb_mbox, event_gen_next);
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
