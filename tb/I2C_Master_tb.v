`timescale 1ns / 1ps

module I2C_Master_tb;
    parameter DATA_WIDTH = 8;
    reg clk_tb, rst_tb, enable_tb;
    reg start_tb;
    reg posedge_tick_tb, negedge_tick_tb;
    reg [DATA_WIDTH - 1 :0] tx_data_tb;
    reg rw_tb;
    reg [6:0] slave_addr_tb;
    reg last_byte_tb, load_next_tb;
    
    wire [DATA_WIDTH - 1 :0] rx_data_tb;
    wire busy_tb, done_tb, ack_error_tb;
    
    // I2C shared SDA & SCL bus 
    wire sda;
    wire scl;
    
    // Slave-side SDA driver 
    reg slave_sda_drive;
    
    assign sda = slave_sda_drive ? 1'b0 : 1'bz;
    
    // DUT instantiation 
    I2C_Master #( 
    .DATA_WIDTH(DATA_WIDTH) 
    ) uut (.clk(clk_tb), .rst(rst_tb), .enable(enable_tb), .start(start_tb), .posedge_tick(posedge_tick_tb), 
           .negedge_tick(negedge_tick_tb), .tx_data(tx_data_tb), .rw(rw_tb), .slave_addr(slave_addr_tb), 
           .rx_data(rx_data_tb), .busy(busy_tb), .done(done_tb), .ack_error(ack_error_tb), .sda(sda), .scl(scl),
           .load_next(load_next_tb), .last_byte(last_byte_tb));

    // Clock generator
    always #5 clk_tb = ~clk_tb;
    
    // Monitor
    initial begin
        $monitor(
            "T=%0t | STATE=%0d -> %0d | POS=%b | NEG=%b | SDA=%b | SCL=%b | BUSY=%b | DONE=%b | ACK_ERR=%b",
            $time,
            uut.current_state,
            uut.next_state,
            posedge_tick_tb,
            negedge_tick_tb,
            sda,
            scl,
            busy_tb,
            done_tb,
            ack_error_tb
        );
    end

    // Watchdog - guarantees the sim ends even if a wait() never resolves because of a DUT bug.
    initial begin
        #50000;
        $display("[TIMEOUT] Watchdog expired - a wait() condition never resolved");
        $finish;
    end

    // Verification variables
    integer pass_count, fail_count, total_tests, i;
    reg [DATA_WIDTH-1:0] expected_data;

    // Waveform dump
    initial begin
        $dumpfile("I2C_Master_tb.vcd");
        $dumpvars(0, I2C_Master_tb);
    end
    
    initial begin
        clk_tb = 0;
        rst_tb = 1;
        enable_tb = 0;
        start_tb = 0;
        posedge_tick_tb = 0;
        negedge_tick_tb = 0;
        tx_data_tb = 0;
        rw_tb = 0;
        slave_addr_tb = 0;
        slave_sda_drive = 0;
        load_next_tb = 0;
        last_byte_tb = 0;
        i = 0;
        
        #20;
        rst_tb = 0;
        enable_tb = 1;
    end
    
    //-------------------------------------------------------------------------------------------------------------
    // DRIVER TASKS
    //-------------------------------------------------------------------------------------------------------------
    
    // 1. Fake slave's SDA driver
    task slave_drive_low;
    begin
        slave_sda_drive = 1'b1;
    end
    endtask
    
    
    task slave_release_sda;
    begin
        slave_sda_drive = 1'b0;
    end
    endtask
    
    // 2. SCL Cycle
    task scl_cycle;
    begin
        negedge_tick_tb = 1;
        #10;
        negedge_tick_tb = 0;
    
        #40;
    
        posedge_tick_tb = 1;
        #10;
        posedge_tick_tb = 0;
    
        #40;
    end
    endtask
    
    // 3. Slave ACK
    task slave_ack;
    begin
        slave_sda_drive = 1'b1;   // Slave pulls SDA LOW
        scl_cycle;                // ACK clock pulse
        slave_sda_drive = 1'b0;   // Release SDA
    end
    endtask

    // 4. Slave sends one byte to master
    task slave_send_byte;
        input [DATA_WIDTH-1:0] data;
    begin
        for (i = DATA_WIDTH-1; i >= 0; i = i-1) begin
    
            // SDA must be stable while SCL is HIGH.
            // Change SDA while SCL is LOW.
            if (data[i] == 1'b0)
                slave_drive_low;
            else
                slave_release_sda;
    
            scl_cycle;
        end
    end
    endtask
    
    // 5. Start an I2C transaction
    task start_transaction;
    begin
        start_tb = 1'b1;
        @(posedge clk_tb);   // FSM samples start here
        @(negedge clk_tb);
        start_tb = 1'b0;
    end
    endtask

    // 6. Complete I2C WRITE transaction
    task write_transaction;
        input [6:0] address;
        input [DATA_WIDTH-1:0] data;
    begin
        // Configure transaction
        rw_tb         = 1'b0;
        slave_addr_tb = address;
        tx_data_tb    = data;
        last_byte_tb  = 1'b1;   // Single-byte write is always the last byte.
        load_next_tb  = 1'b0;   // No next byte for a single-byte transfer.

        // Start transaction
        start_transaction;

        // Address + R/W = 8 bits
        repeat (8)
            scl_cycle;

        // Slave ACK after address
        slave_ack;

        // Data byte
        repeat (DATA_WIDTH)
            scl_cycle;

        // Slave ACK after data
        slave_ack;

        // Wait for one more cycle for STOP
        while (!done_tb)
            scl_cycle;
    end
    endtask


    // 7. General READ result checker
    task check_read_result;
        input [DATA_WIDTH-1:0] expected;
        input [DATA_WIDTH-1:0] actual;
        input [DATA_WIDTH-1:0] test_number;

    begin
        if (actual === expected && !ack_error_tb) begin
            $display("[PASS] Test %0d: Expected = %h, Received = %h", test_number, expected, actual);
            pass_count = pass_count + 1;
        end
    
        else begin
            $display("[FAIL] Test %0d: Expected = %h, Received = %h, ACK_ERROR = %b", test_number, expected, 
            actual, ack_error_tb);
            fail_count = fail_count + 1;
        end

        total_tests = total_tests + 1;
    end
    endtask
    
    // 8. General WRITE result checker
    task check_write_result;
        input [DATA_WIDTH-1:0] test_number;
    begin
        if (done_tb && !ack_error_tb) begin
            $display("[PASS] Test %0d: WRITE transaction completed successfully.", test_number);
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] Test %0d: WRITE transaction failed. DONE = %b, ACK_ERROR = %b",
                      test_number, done_tb, ack_error_tb);
            fail_count = fail_count + 1;
        end
    
        total_tests = total_tests + 1;
    end
    endtask

    //----------------------------------------------------------------------------------------------------------------
    // TEST SEQUENCE 
    //----------------------------------------------------------------------------------------------------------------
    
    initial begin
        pass_count  = 0;
        fail_count  = 0;
        total_tests = 0;
    
        // Wait for reset completion
        @(negedge rst_tb);
        @(posedge clk_tb);
    
        // ------------------------------------------------------------
        // TEST 1 : Single-byte WRITE (ACK)
        expected_data = 8'hA5;
        write_transaction(7'h42, expected_data);
        check_write_result(1);
    
        // ------------------------------------------------------------
        // TEST 2 : Single-byte WRITE (Different Address)
        expected_data = 8'h3C;
        write_transaction(7'h55, expected_data);
        check_write_result(2);
    
        // ------------------------------------------------------------
        // TEST 3 : Write 0x00
        expected_data = 8'h00;
        write_transaction(7'h12, expected_data);
        check_write_result(3);
    
        // ------------------------------------------------------------
        // TEST 4 : Write 0xFF
        expected_data = 8'hFF;
        write_transaction(7'h12, expected_data);
        check_write_result(4);
    
        // ------------------------------------------------------------
        // TEST 5 : Write 0xAA
        expected_data = 8'hAA;
        write_transaction(7'h2A, expected_data);
        check_write_result(5);
    
        // ------------------------------------------------------------
        // TEST 6 : Write 0x55
        expected_data = 8'h55;
        write_transaction(7'h2A, expected_data);
        check_write_result(6);
    
        // ------------------------------------------------------------
        // Back-to-Back WRITE 
        // TEST 7: First Transaction
        expected_data = 8'h11;
        write_transaction(7'h33, expected_data);
        check_write_result(7);
        
        // TEST 8: Second Transaction
        expected_data = 8'h22;
        write_transaction(7'h33, expected_data);
        check_write_result(8);
 
        // ------------------------------------------------------------
        // TEST 9 : Multi-byte WRITE (2 Bytes)
        
        rw_tb         = 1'b0;
        slave_addr_tb = 7'h42;
        
        // First byte
        tx_data_tb    = 8'hA5;
        load_next_tb  = 0;
        last_byte_tb  = 0;
        
        start_transaction();
        
        // Address
        repeat (8)
            scl_cycle;
        
        // Address ACK
        slave_ack;
        
        // First byte
        repeat (8)
            scl_cycle;
        
        // ACK after first byte
        tx_data_tb   = 8'h3C;
        load_next_tb = 1;
        slave_ack;
        load_next_tb = 0;
        
        // Second byte
        repeat (8)
            scl_cycle;
        
        // ACK after second byte
        last_byte_tb = 1;
        slave_ack;
        last_byte_tb = 0;
        
        // Wait for STOP
        while (!done_tb)
            scl_cycle;
        
        check_write_result(9);
 
        // ------------------------------------------------------------
        // TEST 10 : Multi-byte WRITE (NACK on Second Byte)
        
        rw_tb         = 1'b0;
        slave_addr_tb = 7'h42;
        tx_data_tb    = 8'hA5;
        
        last_byte_tb  = 1'b0;
        load_next_tb  = 1'b1;
        
        start_transaction();
        
        repeat (8)
            scl_cycle;

        slave_ack();
        
        // First Byte
        repeat (DATA_WIDTH)
            scl_cycle;
        
        // Prepare next byte BEFORE ACK
        tx_data_tb    = 8'h3C;
        load_next_tb  = 1'b1;
        last_byte_tb  = 1'b0;
            
        // ACK first byte
        slave_ack();
            
        load_next_tb = 1'b0;
            
        // Second byte
        repeat(DATA_WIDTH)
            scl_cycle;
            
        // NACK second byte
        last_byte_tb = 1'b1;
        slave_release_sda();
          scl_cycle();
        
        while (!done_tb)
            scl_cycle;
        
        // Check result
        if (done_tb && ack_error_tb) begin
            $display("[PASS] Test 10: Multi-byte WRITE stopped after NACK.");
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] Test 10: Expected ACK_ERROR=1, DONE=1. ACK_ERROR=%b DONE=%b",
                      ack_error_tb, done_tb);
            fail_count = fail_count + 1;
        end
        total_tests = total_tests + 1;
 
        // ------------------------------------------------------------
        // TEST SUMMARY
        // ------------------------------------------------------------
        $display("\n========================================");
        $display("          I2C MASTER TEST SUMMARY");
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
