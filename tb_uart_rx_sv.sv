`timescale 1ns / 1ps
`define BIT_PERIOD (100_000_000/9600)
interface uart_rx_interface;
    logic       clk;
    logic       rst;
    logic       rx;
    logic       b_tick;
    logic       rx_done;
    logic [7:0] rx_data;

endinterface

class transaction;
    //generator: 랜텀 8비트 데이터 생성. -> 8bit -> driver
    //driver: 1bit -> dut
    //dut: rx핀을 다시 8비트로 조립. 조립이 끝나면 rx_done=1, rx_data 8비트를 내보냄.
    //monitor: rx_done==1이 되는 순간 rx_data를 scoreboard로 전달.
    //scb: generator값과 monitor값을 비교해서 pass fail.
    //bit            rst;
    //bit            rx;
    //bit            b_tick;
    //bit            rx_done;
    rand bit [7:0] rx_data;

    //디버깅용 display 함수
    function debug_print(string name);
        $display("%t [%s] : rx_data = %d", $time, name, rx_data);
    endfunction
endclass

class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event event_gen_next;
    function new(mailbox#(transaction) gen2drv_mbox, event event_gen_next,
                 mailbox#(transaction) gen2scb_mbox);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.event_gen_next = event_gen_next;
        this.gen2scb_mbox   = gen2scb_mbox;
    endfunction

    task run(int count);
        repeat (count) begin
            tr = new;
            tr.randomize();
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
    virtual uart_rx_interface uart_vif;
    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual uart_rx_interface uart_vif);
        this.gen2drv_mbox = gen2drv_mbox;
        this.uart_vif     = uart_vif;
    endfunction

    task preset();
        uart_vif.rst = 1;
        uart_vif.rx  = 1;  //idle

        repeat (2) @(posedge uart_vif.clk);
        uart_vif.rst = 0;
        @(negedge uart_vif.clk);
        //preset에서는 rx=0까진X
    endtask
    task run();
        forever begin
            gen2drv_mbox.get(tr);
            tr.debug_print("DRV");
            @(posedge uart_vif.clk);
            //#1;
            //start bit
            uart_vif.rx = 0;
            #(`BIT_PERIOD);
            //data bit
            for (int i = 0; i < 8; i++) begin
                uart_vif.rx = tr.rx_data[i];
                #(`BIT_PERIOD);
            end
            //stop bit
            uart_vif.rx = 1;
            #(`BIT_PERIOD);
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
            @(posedge uart_vif.rx_done);
            #1;
            tr = new;
            tr.rx_data = uart_vif.rx_data;
            mon2scb_mbox.put(tr);
            tr.debug_print("MON");
        end
    endtask
endclass

class scoreboard;
    transaction tr_exp;
    transaction tr_act;
    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event event_gen_next;
    function new(mailbox#(transaction) mon2scb_mbox, event event_gen_next,
                 mailbox#(transaction) gen2scb_mbox);
        this.mon2scb_mbox   = mon2scb_mbox;
        this.event_gen_next = event_gen_next;
        this.gen2scb_mbox   = gen2scb_mbox;
    endfunction
    task run();
        forever begin
            mon2scb_mbox.get(tr_act);
            gen2scb_mbox.get(tr_exp);
            $display("SCB");
            if (tr_exp.rx_data == tr_act.rx_data) begin
                $display("[SCB] PASS !!");
            end else begin
                $display("%t [SCB] FAIL : exp.rx_data = %d, act.rx_data = %d",
                         $time, tr_exp.rx_data, tr_act.rx_data);
            end
            ->event_gen_next;
        end
    endtask
endclass

class environment;
    generator                 gen;
    driver                    drv;
    monitor                   mon;
    scoreboard                scb;
    mailbox #(transaction)    gen2drv_mbox;
    mailbox #(transaction)    mon2scb_mbox;
    mailbox #(transaction)    gen2scb_mbox;
    event                     event_gen_next;
    virtual uart_rx_interface uart_vif;
    function new(virtual uart_rx_interface uart_vif);
        gen2drv_mbox = new;
        mon2scb_mbox = new;
        gen2scb_mbox = new;
        gen = new(gen2drv_mbox, event_gen_next, gen2scb_mbox);
        drv = new(gen2drv_mbox, uart_vif);
        mon = new(mon2scb_mbox, uart_vif);
        scb = new(mon2scb_mbox, event_gen_next, gen2scb_mbox);
        this.uart_vif = uart_vif;
    endfunction
    task run();
        drv.preset();
        fork
            gen.run(10);
            drv.run();
            mon.run();
            scb.run();
        join_any
        disable fork;
        repeat (10) #(`BIT_PERIOD);
        $display("test bench finished");
        $stop;
    endtask
endclass

module tb_uart_rx_sv ();  //tb_uart_sv

    uart_rx_interface uart_if ();
    environment env;

    uart_rx_sv dut (
        .clk    (uart_if.clk),
        .rst    (uart_if.rst),
        .rx     (uart_if.rx),
        .b_tick (uart_if.b_tick),
        .rx_done(uart_if.rx_done),
        .rx_data(uart_if.rx_data)
    );

    b_tick_gen dut2 (
        .clk   (uart_if.clk),
        .rst   (uart_if.rst),
        .b_tick(uart_if.b_tick)
    );

    always #5 uart_if.clk = ~uart_if.clk;


    initial begin
        uart_if.clk = 0;
        uart_if.rst = 0;
        uart_if.rx = 1;
        env = new(uart_if);
        env.run();
    end
    initial begin
        forever begin
            @(posedge uart_if.rx_done);
            $display("%t [TB] rx_done detected! rx_data=%d", $time,
                     uart_if.rx_data);
        end
    end
    initial begin
        forever begin
            @(posedge uart_if.b_tick);
            $display("%t [TB] b_tick!", $time);
        end
    end

endmodule
