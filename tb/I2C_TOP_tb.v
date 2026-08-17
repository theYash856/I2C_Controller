`timescale 1ns / 1ps

module I2C_TOP_tb;
    parameter DATA_WIDTH = 8;
    parameter CLK_FREQ = 100_000_000; // 100 MHz
    parameter I2C_FREQ = 100_000;     // 100 KHz
    
    reg clk_tb;
    reg rst_tb;
    reg enable_tb;

    // Master Interface
    reg start_tb;
    reg rw_tb;
    reg [6:0] master_slave_addr_tb;
    reg [6:0] slave_addr_cfg_tb;
    reg [DATA_WIDTH-1:0] tx_data_tb;
    reg load_next_tb;
    reg last_byte_tb;

    // Master Outputs
    wire [DATA_WIDTH-1:0] rx_data_tb;
    wire busy_tb;
    wire done_tb;
    wire ack_error_tb;

    // I2C Bus
    wire sda_tb;
    pullup(sda_tb);
    wire scl_tb;
    pullup(scl_tb);

    // Slave Debug Outputs
    wire [DATA_WIDTH-1:0] slave_rx_data_tb;
    wire slave_busy_tb;
    wire slave_done_tb;
    wire addr_match_tb;
    
    I2C_TOP #(.DATA_WIDTH(DATA_WIDTH), .CLK_FREQ(CLK_FREQ), .I2C_FREQ(I2C_FREQ)
    ) uut (.clk(clk_tb), .rst(rst_tb), .enable(enable_tb), .start(start_tb), .rw(rw_tb), 
           .master_slave_addr(master_slave_addr_tb), .slave_addr_cfg(slave_addr_cfg_tb), .tx_data(tx_data_tb), 
           .load_next(load_next_tb), .last_byte(last_byte_tb), .rx_data(rx_data_tb), .busy(busy_tb),
           .done(done_tb), .ack_error(ack_error_tb), .sda(sda_tb), .scl(scl_tb), .slave_rx_data(slave_rx_data_tb),
           .slave_busy(slave_busy_tb), .slave_done(slave_done_tb), .addr_match(addr_match_tb));
           
    // System Clock generator
    always #5 clk_tb = ~clk_tb;
    
    // Waveform dump
    initial begin
        $dumpfile("I2C_TOP_tb.vcd");
        $dumpvars(0, I2C_TOP_tb);
    end
    
    // Watchdog
    initial begin
        #5_000_000;
        $display("[TIMEOUT] Watchdog expired - a wait() condition never resolved");
        $finish;
    end
    
    // Monitor
    initial begin
        $monitor("T=%0t | scl=%b | sda=%b | m_state=%0d | s_state=%0d | busy=%b | s_busy=%b | enable=%b",
                  $time, scl_tb, sda_tb, uut.master.current_state, uut.slave.current_state,
                  busy_tb, slave_busy_tb, enable_tb);
    end
    
    // Verification variables
    integer pass_count, fail_count, total_tests;
    
    //-------------------------------------------------------------------------------------------------------------
    // DRIVER TASKS
    //-------------------------------------------------------------------------------------------------------------
    
    // Task 1: Reset DUT
    task reset_dut;
    begin
        rst_tb        = 1'b1;
        enable_tb     = 1'b0;
        start_tb      = 1'b0;
        rw_tb         = 1'b0;
        tx_data_tb    = 0;
        master_slave_addr_tb = 7'h42;
        slave_addr_cfg_tb = 7'h42;
        load_next_tb  = 1'b0;
        last_byte_tb  = 1'b1;
    
        #20;
        rst_tb    = 1'b0;
        enable_tb = 1'b1;
        #20;
    end
    endtask
    
    // Task 2: Disable DUT
    task disable_dut;
    begin
        enable_tb = 1'b0;
        #50;
    end
    endtask
      
    // Task 3: Enable DUT
    task enable_dut;
    begin
        enable_tb = 1'b1;
        #50;
    end
    endtask
    
    // Task 4: Start Single-Byte WRITE Transaction
    task start_write;
    input [6:0] addr;
    input [DATA_WIDTH-1:0] data;
    begin
        master_slave_addr_tb = addr;
        tx_data_tb    = data;
        rw_tb         = 1'b0;
        load_next_tb  = 1'b0;
        last_byte_tb  = 1'b1;
        start_tb = 1'b1;
        #10;
        start_tb = 1'b0;
    end
    endtask
    
    // Task 5: Start Single-Byte READ Transaction
    task start_read;
    input [6:0] addr;
    input [DATA_WIDTH-1:0] slave_data;
    begin
        master_slave_addr_tb = addr;
        tx_data_tb    = slave_data;    // Data preloaded into slave
        rw_tb         = 1'b1;
        load_next_tb  = 1'b0;
        last_byte_tb  = 1'b1;
    
        start_tb = 1'b1;
        #10;
        start_tb = 1'b0;
    end
    endtask
   
    // Task 6: Multi-byte Transfer
    task multi_byte_transfer;
    input [DATA_WIDTH-1:0] data;
    input last;
    begin
        tx_data_tb   = data;
        last_byte_tb = last;
    
        load_next_tb = 1'b1;
        #10;
        load_next_tb = 1'b0;
    end
    endtask
    
    // Task 7: Wait for Transaction Completion
    task wait_done;
    begin
        wait(done_tb);
        #20;
    end
    endtask
    
    // Task 8: General Test Checker
    task check_test;
        input [DATA_WIDTH-1:0] expected;
        input [DATA_WIDTH-1:0] actual;
        input integer test_number;
        input [8*40-1:0] test_name;
    begin
        if (actual === expected) begin
            $display("[PASS] Test %0d (%0s): Expected = %h, Received = %h",
                     test_number, test_name, expected, actual);
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] Test %0d (%0s): Expected = %h, Received = %h",
                     test_number, test_name, expected, actual);
            fail_count = fail_count + 1;
        end
        total_tests = total_tests + 1;
    end
    endtask

    initial begin
    pass_count  = 0;
    fail_count  = 0;
    total_tests = 0;

    clk_tb        = 0;
    rst_tb        = 1;
    enable_tb     = 0;
    start_tb      = 0;
    rw_tb         = 0;
    tx_data_tb    = 0;
    master_slave_addr_tb = 7'h42;
    slave_addr_cfg_tb    = 7'h42;
    load_next_tb  = 0;
    last_byte_tb  = 1;

    #20;
    rst_tb    = 0;
    enable_tb = 1;
    
    //------------------------------------------------------------------
    // TEST SEQUENCE
    //------------------------------------------------------------------
    // Test 1 : Address Match
    reset_dut();

    start_write(7'h42, 8'h55);
    wait_done();

    check_test(8'h01, {7'b0, addr_match_tb}, 1, "Address Match");

    //------------------------------------------------------------------
    // Test 2 : Address Mismatch
    reset_dut();
    slave_addr_cfg_tb = 7'h42;      // slave remains at 0x42
    start_write(7'h33, 8'h55);      // master sends 0x33

    wait_done();
    check_test(8'h00, {7'b0, addr_match_tb}, 2, "Address Mismatch");

    //------------------------------------------------------------------
    // Test 3 : Single Byte WRITE
    reset_dut();

    start_write(7'h42, 8'hA5);
    wait_done();

    check_test(8'hA5, slave_rx_data_tb, 3, "Single Byte WRITE");

    //------------------------------------------------------------------
    // Test 4 : Single Byte READ
    reset_dut();

    start_read(7'h42, 8'h3C);
    wait_done();

    check_test(8'h3C, rx_data_tb, 4, "Single Byte READ");

    //------------------------------------------------------------------
    // Test 5 : Multi Byte WRITE
    reset_dut();
    start_write(7'h42, 8'h11);

    wait(busy_tb);

    multi_byte_transfer(8'h22, 1'b1);
    wait_done();
    check_test(8'h22, slave_rx_data_tb, 5, "Multi Byte WRITE");

    //------------------------------------------------------------------
    // Test 6 : Multi Byte READ
    reset_dut();
    start_read(7'h42, 8'h55);

    wait(busy_tb);

    multi_byte_transfer(8'hAA, 1'b1);
    wait_done();
    check_test(8'hAA, rx_data_tb, 6, "Multi Byte READ");

    //------------------------------------------------------------------
    // Test 7 : Disable during Transaction
    reset_dut();
    start_write(7'h42, 8'h66);

    #200;
    disable_dut();
    check_test(8'h00, {7'b0,busy_tb}, 7, "Disable During Transaction");

    enable_dut();

    //------------------------------------------------------------------
    // Test Summary
    //------------------------------------------------------------------
    $display("\n========================================");
    $display("             I2C TOP TEST SUMMARY");
    $display("========================================");
    $display("Total Tests : %0d", total_tests);
    $display("Passed      : %0d", pass_count);
    $display("Failed      : %0d", fail_count);
        if (fail_count == 0)                                   
            $display("RESULT       : ALL TESTS PASSED");       
        else                                                   
            $display("RESULT       : SOME TESTS FAILED");      
                                                               
        $display("========================================\n");
    $finish;
    end
endmodule
