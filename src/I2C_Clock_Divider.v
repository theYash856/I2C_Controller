`timescale 1ns / 1ps

module I2C_Clock_Divider(
    input clk,
    input rst,
    input enable,
    input busy, // Only toggle while a transaction is in progress
    output reg scl, 
    output reg posedge_tick,
    output reg negedge_tick
    );
    
    // Configuarable parameters
    parameter CLK_FREQ = 100_000_000; // 100 MHz
    parameter I2C_FREQ = 100_000;     // 100 KHz
    
    // One SCL period consists of LOW and HIGH phases, so the clock must toggle twice per SCL period.
    localparam CLK_DIV = CLK_FREQ / (2 * I2C_FREQ); 
    
    // Internal Register 
    reg [$clog2(CLK_DIV + 1) - 1: 0] counter;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            scl <= 1;   // I2C bus must return to its idle state: SCL released HIGH.
            counter <= 0;
            posedge_tick <= 0;
            negedge_tick <= 0;
        end
        
        else if (!enable || !busy) begin
            scl <= 1;
            counter <= 0;
            posedge_tick <= 0;
            negedge_tick <= 0;
        end
        
        else begin
            posedge_tick <= 0;
            negedge_tick <= 0;
            
            if (counter == CLK_DIV - 1) begin
                counter <= 0;
                scl <= ~scl; // Toggling
                
                if (scl == 0) begin // Toggling to 1
                    posedge_tick <= 1'b1;
                    negedge_tick <= 1'b0;
                end
                
                else if (scl == 1) begin // Toggling to 0
                    negedge_tick <= 1'b1;
                    posedge_tick <= 1'b0;
                end
            end
                
            else begin
                counter <= counter + 1;
            end
        end
    end
endmodule
