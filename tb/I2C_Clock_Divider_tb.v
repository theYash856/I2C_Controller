`timescale 1ns / 1ps

module I2C_Clock_Divider_tb;

    reg clk_tb, rst_tb;
    reg enable_tb;
    reg busy_tb;
    
    wire scl_tb;
    wire posedge_tick_tb, negedge_tick_tb;
    
    // Instantiation of DUT
    I2C_Clock_Divider #(
        .CLK_FREQ(100_000_000),
        .I2C_FREQ(1_000_000)    // 1 MHz
    )
    uut (.clk(clk_tb), .rst(rst_tb), .enable(enable_tb), .scl(scl_tb), .busy(busy_tb), .posedge_tick(posedge_tick_tb), 
         .negedge_tick(negedge_tick_tb));
    
    // Clock Generator
    always #5 clk_tb = ~clk_tb;
    
    // Monitor
    initial begin
        $monitor(
            "T=%0t | ENABLE=%b BUSY=%b | SCL=%b | POS_TICK=%b | NEG_TICK=%b",
            $time,
            enable_tb,
            busy_tb,
            scl_tb,
            posedge_tick_tb,
            negedge_tick_tb
        );
    end
    
    // Verification Variables
    integer pass_count;
    integer fail_count;
    integer total_tests;
        
    initial begin
        clk_tb = 0;
        rst_tb = 0;
        enable_tb = 0;
        busy_tb   = 0;

        pass_count  = 0;
        fail_count  = 0;
        total_tests = 0;
    end

    // Waveform Dump
    initial begin
        $dumpfile("I2C_Clock_Divider_tb.vcd");
        $dumpvars(0, I2C_Clock_Divider_tb);
    end
    
    //---------------------------------------------------------------------------
    // DRIVER TASKS
    //---------------------------------------------------------------------------  

    // 1. Reset DUT
    task reset_dut;
    begin
        rst_tb = 1;
        repeat(2) @(posedge clk_tb);
        rst_tb = 0;
        @(posedge clk_tb);
    end
    endtask
    
    // 2. Disable DUT
    task disable_dut;
    begin
        enable_tb = 0;
        @(posedge clk_tb);
        #1;
    end
    endtask
    
    // 3. Enable DUT
    task enable_dut;
    begin
        enable_tb = 1;
        @(posedge clk_tb);
    end
    endtask
 
    //---------------------------------------------------------------------------
    // CHECKING TASK
    //---------------------------------------------------------------------------
    
    task check_outputs;
        input expected_scl;
        input expected_posedge_tick;
        input expected_negedge_tick;
        input [127:0] test_name;
        
        begin
            total_tests = total_tests + 1;
            
            if ((scl_tb === expected_scl) && (posedge_tick_tb === expected_posedge_tick) &&
                (negedge_tick_tb === expected_negedge_tick)) begin
                
                $display("[PASS] %s | SCL=%b, Posedge_Tick=%b, Negedge_Tick=%b",
                         test_name, scl_tb, posedge_tick_tb, negedge_tick_tb);
                pass_count = pass_count + 1;
            end
            
            else begin
                $display("[FAIL] %s | Expected: SCL=%b, Posedge_Tick=%b, Negedge_Tick=%b | Got: SCL=%b, Posedge_Tick=%b, Negedge_Tick=%b",
                         test_name,
                         expected_scl, expected_posedge_tick, expected_negedge_tick,
                         scl_tb, posedge_tick_tb, negedge_tick_tb);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    //---------------------------------------------------------------------------
    //TEST SEQUENCE
    //---------------------------------------------------------------------------
    
    initial begin
    
    // CD-01: Reset DUT
    reset_dut;
    check_outputs(1'b1, 1'b0, 1'b0, "CD-01 Reset");
    
    // CD-02: Test Rising Edge
    reset_dut;
    enable_dut;
    busy_tb = 1;
    @(posedge posedge_tick_tb);
    check_outputs(1'b1, 1'b1, 1'b0, "CD-02 Rising Edge");
    
    // CD-03: Test Falling Edge
    @(posedge negedge_tick_tb);
    check_outputs(1'b0, 1'b0, 1'b1, "CD-03 Falling Edge");
    
    // CD-04: Disable DUT
    disable_dut;
    check_outputs(1'b1, 1'b0, 1'b0, "CD-04 Disable");
    
    // CD-05: Renable DUT
    enable_dut;
    @(posedge posedge_tick_tb);
    check_outputs(1'b1, 1'b1, 1'b0, "CD-05 Re-enable");
    
    $display("\n========================================");
    $display("    I2C CLOCK DIVIDER TEST SUMMARY");
    $display("========================================");
    $display("Total Checks : %0d", total_tests);
    $display("Passed       : %0d", pass_count);
    $display("Failed       : %0d", fail_count);
    
    if (fail_count == 0)
        $display("RESULT       : ALL TESTS PASSED");
    else
        $display("RESULT       : SOME TESTS FAILED");
    
    $display("========================================\n");
    $finish;
    end
endmodule
