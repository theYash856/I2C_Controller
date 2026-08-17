`timescale 1ns / 1ps

module I2C_Slave_tb;
    parameter DATA_WIDTH = 8;

    reg  clk_tb, rst_tb, enable_tb;
    reg  [DATA_WIDTH-1:0] tx_data_tb;
    reg  [6:0] slave_addr_tb;
    
    wire [DATA_WIDTH-1:0] rx_data_tb;
    wire busy_tb, done_tb, addr_match_tb;

    // I2C shared bus
    wire sda;
    pullup(sda);
    reg  scl_tb;   // driven entirely by the fake master task set
    
    // Fake master's SDA driver
    reg master_sda_drive;
    assign sda = master_sda_drive ? 1'b0 : 1'bz;
    
    reg [DATA_WIDTH-1:0] read_data;  // Captures data transmitted by the slave during a READ operation.

    // DUT instantiation
    I2C_Slave #(
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (.clk(clk_tb), .rst(rst_tb), .enable(enable_tb), .tx_data(tx_data_tb), .slave_addr(slave_addr_tb),
           .sda(sda), .scl(scl_tb), .rx_data(rx_data_tb), .busy(busy_tb), .done(done_tb), .addr_match(addr_match_tb));

    // System Clock generator
    always #5 clk_tb = ~clk_tb;

    // Waveform dump
    initial begin
        $dumpfile("I2C_Slave_tb.vcd");
        $dumpvars(0, I2C_Slave_tb);
    end

    // Watchdog
    initial begin
        #500000;
        $display("[TIMEOUT] Watchdog expired - a wait() condition never resolved");
        $finish;
    end

    // Monitor
    initial begin
    $monitor(
        "T=%0t | STATE=%0d -> %0d | SCL=%b | SDA=%b | ADDR_MATCH=%b | BUSY=%b | DONE=%b | RX=%h",
        $time,
        uut.current_state,
        uut.next_state,
        scl_tb,
        sda,
        addr_match_tb,
        busy_tb,
        done_tb,
        rx_data_tb
    );
    end

    // Verification variables
    integer pass_count, fail_count, total_tests, i;

    initial begin
        clk_tb           = 0;
        rst_tb           = 1;
        enable_tb        = 0;
        tx_data_tb       = 0;
        slave_addr_tb    = 7'h42;   // Slave's own configured address
        scl_tb           = 1;
        master_sda_drive = 0;       // Released (SDA high) at idle
        read_data        = 0;
        i = 0;
        pass_count  = 0;
        fail_count  = 0;
        total_tests = 0;

        #20;
        rst_tb    = 0;
        enable_tb = 1;
    end
    
    //-------------------------------------------------------------------------------------------------------------
    // DRIVER TASKS
    //-------------------------------------------------------------------------------------------------------------
    
    // Task 1: Reset DUT
    task reset_dut;
    begin
        rst_tb = 1'b1;
        enable_tb = 1'b0;
        scl_tb = 1'b1;
        master_sda_drive = 1'b0;
    
        #20;
        rst_tb = 1'b0;
        enable_tb = 1'b1;
        #20;
    end
    endtask
    
    // Task 2: SCL Cycle (one pulse)
    task scl_cycle;
    begin
        #20;
        scl_tb = 1'b1;
        #20;
        scl_tb = 1'b0;
    end
    endtask
    
    // Task 3: Start Condition
    task start_condition;
    begin
        master_sda_drive = 1'b0;
        scl_tb = 1'b1;
        #20;
    
        master_sda_drive = 1'b1;      
        #20;
    
        scl_tb = 1'b0;
    end
    endtask
    
    // Task 4: Stop Condition
    task stop_condition;
    begin
        master_sda_drive = 1'b1;      // Hold SDA Low
        scl_tb = 1'b0;
        #20;
    
        scl_tb = 1'b1;
        #20;
    
        master_sda_drive = 1'b0;      // SDA goes High
        #20;
    end
    endtask
    
    // Task 5: Fake Master sends byte
    task send_byte;
    input [DATA_WIDTH-1:0] data;
    begin
        for(i=7;i>=0;i=i-1) begin
            master_sda_drive = ~data[i];   // 0: drive low, 1: release
            scl_cycle;
        end
    
        master_sda_drive = 1'b0;           // Release SDA for ACK
    end
    endtask
    
    // Task 6: Fake Master receives byte
    task read_byte;
    output [DATA_WIDTH-1:0] data;
    begin
        master_sda_drive = 1'b0;   
    
        for(i=7;i>=0;i=i-1) begin
            #20;
            scl_tb = 1'b1;
            #10;
            data[i] = sda;
            #10;
            scl_tb = 1'b0;
        end
    end
    endtask
    
    // Task 7: Master ACK
    task master_ack;
    begin
        master_sda_drive = 1'b1;   // Pull SDA Low
        scl_cycle;
        master_sda_drive = 1'b0;   // Release SDA
    end
    endtask
    
    // Task 8: Master NACK
    task master_nack;
    begin
        master_sda_drive = 1'b0;   // Leave SDA High
        scl_cycle;
    end
    endtask
    
    // Task 9: Check Slave ACK
    task check_slave_ack;
    begin
        master_sda_drive = 1'b0;
        #20;
        scl_tb = 1'b1;
        #10;
    
        if (sda !== 1'b0)
            $display("Slave ACK FAILED");
    
        #10;
        scl_tb = 1'b0;
    end
    endtask
    
    // Task 10: General test checker
    task check_test;
        input [DATA_WIDTH-1:0] expected;
        input [DATA_WIDTH-1:0] actual;
        input integer test_number;
        input [160:0] test_name;
    
    begin
        if (actual === expected) begin
            $display("[PASS] Test %0d (%0s): Expected = %h, Received = %h", test_number, test_name, expected, actual);
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] Test %0d (%0s): Expected = %h, Received = %h", test_number, test_name, expected, actual);
            fail_count = fail_count + 1;
        end
        total_tests = total_tests + 1;
    end
    endtask
    
    //----------------------------------------------------------------------------------------------------------------
    // TEST SEQUENCE 
    //----------------------------------------------------------------------------------------------------------------
    initial begin
    
    reset_dut();

    //--------------------------------------------------------------------------
    // Test 1 : Address Match
    start_condition();
    send_byte({slave_addr_tb, 1'b0});
    check_slave_ack();
    
    #20;   // allow addr_match to update
    check_test(8'h01, {7'b0, addr_match_tb}, 1, "Address Match");
    
    stop_condition();

    //--------------------------------------------------------------------------
    // Test 2 : Address Mismatch
    start_condition();
    send_byte({7'h55, 1'b0});
    stop_condition();

    #50;
    check_test(8'h00, {7'b0, addr_match_tb}, 2, "Address Mismatch");

    //--------------------------------------------------------------------------
    // Test 3 : Single-Byte WRITE
    start_condition();
    send_byte({slave_addr_tb, 1'b0});
    check_slave_ack();

    send_byte(8'hA5);
    check_slave_ack();

    stop_condition();

    #50;
    check_test(8'hA5, rx_data_tb, 3, "Single Byte WRITE");

    //--------------------------------------------------------------------------
    // Test 4 : Single-Byte READ
    tx_data_tb = 8'h3C;

    start_condition();
    send_byte({slave_addr_tb, 1'b1});
    check_slave_ack();

    read_byte(read_data);

    master_nack();
    stop_condition();

    #50;
    check_test(8'h3C, read_data, 4, "Single Byte READ");

    //--------------------------------------------------------------------------
    // Test 5 : Multi-Byte WRITE
    start_condition();
    send_byte({slave_addr_tb, 1'b0});
    check_slave_ack();

    send_byte(8'h11);
    check_slave_ack();

    send_byte(8'h22);
    check_slave_ack();

    stop_condition();

    #50;
    check_test(8'h22, rx_data_tb, 5, "Multi Byte WRITE");

    //--------------------------------------------------------------------------
    // Test 6 : Multi-Byte READ
    tx_data_tb = 8'h55;

    start_condition();
    send_byte({slave_addr_tb, 1'b1});
    check_slave_ack();

    read_byte(read_data);
    check_test(8'h55, read_data, 6, "Multi Byte READ - Byte 1");

    // Send next byte before calling master_ack
    tx_data_tb = 8'hAA;
    master_ack();
    
    read_byte(read_data);
    check_test(8'hAA, read_data, 7, "Multi Byte READ - Byte 2");

    master_nack();
    stop_condition();

    //--------------------------------------------------------------------------
    // Test 7 : Reset During Transaction
    start_condition();
    send_byte({slave_addr_tb, 1'b0});

    rst_tb = 1'b1;
    #20;
    rst_tb = 1'b0;

    #50;
    check_test(8'h00, {7'b0, busy_tb}, 8, "Reset During Transaction");

    //--------------------------------------------------------------------------
    // Test 8 : STOP Detection
    reset_dut();

    start_condition();
    send_byte({slave_addr_tb, 1'b0});
    check_slave_ack();

    stop_condition();

    #50;
    check_test(8'h01, {7'b0, done_tb}, 9, "STOP Detection");

    //--------------------------------------------------------------------------
    // Summary
    //--------------------------------------------------------------------------
    $display("\n========================================");
    $display("           I2C SLAVE TEST SUMMARY");
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