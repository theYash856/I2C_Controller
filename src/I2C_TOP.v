`timescale 1ns / 1ps

module I2C_TOP #(
    parameter DATA_WIDTH = 8,
    parameter CLK_FREQ   = 100_000_000,
    parameter I2C_FREQ   = 100_000
)(
    input  clk,
    input  rst,
    input  enable,

    // Master interface
    input  start,
    input  rw,
    input [6:0] master_slave_addr,
    input [6:0] slave_addr_cfg,
    input  [DATA_WIDTH-1:0] tx_data,
    input load_next,
    input last_byte,
    
    output [DATA_WIDTH-1:0] rx_data,
    output busy,
    output done,
    output ack_error,

    // I2C Bus
    inout  sda,
    output scl,

    // Debug outputs from slave
    output [DATA_WIDTH-1:0] slave_rx_data,
    output slave_busy,
    output slave_done,
    output addr_match
);
 
    wire posedge_tick;
    wire negedge_tick;
    
    // Instantiation 
    
    // 1. Clock Divider
    I2C_Clock_Divider #(.CLK_FREQ(CLK_FREQ), .I2C_FREQ(I2C_FREQ))
               clk_div (.clk(clk), .rst(rst), .enable(enable), .scl(scl), .busy(busy), .posedge_tick(posedge_tick),
                       .negedge_tick(negedge_tick));
    
    // 2. Master
    I2C_Master #(.DATA_WIDTH(DATA_WIDTH))
          master(.clk(clk), .rst(rst), .enable(enable), .start(start), .posedge_tick(posedge_tick), .negedge_tick(negedge_tick),
                 .tx_data(tx_data), .rw(rw), .slave_addr(master_slave_addr), .rx_data(rx_data), .ack_error(ack_error), .done(done),
                 .busy(busy), .sda(sda), .scl(), .load_next(load_next), .last_byte(last_byte));
    
    // 3. Slave
    I2C_Slave #(.DATA_WIDTH(DATA_WIDTH))
          slave(.clk(clk), .rst(rst), .enable(enable), .tx_data(tx_data), .slave_addr(slave_addr_cfg), .sda(sda), .scl(scl),
                .rx_data(slave_rx_data), .busy(slave_busy), .done(slave_done), .addr_match(addr_match));
                
endmodule
