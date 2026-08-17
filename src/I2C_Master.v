`timescale 1ns / 1ps

module I2C_Master #(
    parameter DATA_WIDTH = 8  
    )(
    input clk,
    input rst,
    input enable,
    input start,
    input posedge_tick,
    input negedge_tick,
    input [DATA_WIDTH - 1 :0] tx_data,
    input rw,               // 0 = Write, 1 = Read
    input [6:0] slave_addr, // 7-bit slave address
    
    // For Multi-byte implementation
    input load_next,     // New byte is available
    input last_byte,     // 1 implies it is the final byte
    
    output reg [DATA_WIDTH - 1 :0] rx_data,
    output reg busy,
    output reg done,
    output reg ack_error, // Acknowledgement error
    
    inout sda, // Inout as both transmission and receving uses the same data line
    inout scl
    );
    
    // FSM States 
    localparam IDLE    = 3'b000;
    localparam START   = 3'b001;
    localparam ADDRESS = 3'b010;
    localparam ACK     = 3'b011;
    localparam DATA    = 3'b100;
    localparam STOP    = 3'b101;
    
    localparam ADDR_BITS = 8;   // 7-bit address + R/W
    
    // To make bit_counter work for both address and data phase
    localparam COUNTER_MAX  = (DATA_WIDTH > ADDR_BITS) ? DATA_WIDTH : ADDR_BITS; 
    
    // Internal Registers
    reg [$clog2(COUNTER_MAX + 1) - 1 : 0] bit_counter;
    reg [DATA_WIDTH - 1 : 0] master_shift;
    reg [DATA_WIDTH - 1 : 0] rx_shift;
    reg [7:0] addr_shift; // Slave address + R/W bit
    reg ack_received;
    reg ack_phase; // 0 = ACK after ADDRESS ; 1 = ACK after DATA
    reg stop_ready;
    reg [2:0] current_state, next_state;
    
    reg sda_drive;
    reg scl_drive;
    
    assign sda = sda_drive ? 1'b0 : 1'bz; // High impedence to show that the wire is not driving anything
    assign scl = scl_drive ? 1'b0 : 1'bz;
    
    // Sequential Block
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            bit_counter <= 0;
            rx_data <= 0;
            busy <= 0;
            done <= 0;
            ack_error <= 0;
            ack_phase <= 0;
            master_shift <= 0;
            ack_received <= 0;
            addr_shift    <= 0; 
            sda_drive     <= 0;
            scl_drive     <= 0;
            rx_shift <= 0;
            stop_ready <= 0;
        end
        
        else begin
           if (!enable) begin
             current_state <= IDLE;
             busy          <= 0;
             done          <= 0;
             bit_counter   <= 0;
             ack_phase     <= 0;
             stop_ready    <= 0;
             sda_drive     <= 0;
             scl_drive     <= 0;
            end
            
            else begin 
                current_state <= next_state;
                
                case(current_state)
                    IDLE: begin
                            busy <= 0;
                          end
                          
                   START: begin
                            busy       <= 1;
                            done       <= 0;
                            stop_ready <= 0;
                            ack_error  <= 0;
                            ack_phase  <= 0;
                            addr_shift <= {slave_addr, rw};
        
                            scl_drive   <= 0;   // SCL HIGH
                            sda_drive   <= 1;   
                            bit_counter <= 0;
                          
                            if (rw == 1'b1)
                                rx_shift <= 0;  // To ensure the register is empty.
                          end
                    
                    ADDRESS: begin
                               busy <= 1;
                               // SCL goes LOW; prepare next bit
                               if (negedge_tick) begin
                                   scl_drive <= 1;      
                                   
                                   sda_drive   <= ~addr_shift[7];
                                   addr_shift  <= addr_shift << 1;
                               end
                           
                               // SCL goes HIGH; bit was sampled
                               if (posedge_tick) begin
                                   scl_drive <= 0;      
                                   bit_counter <= bit_counter + 1;
                               end
                           end
                    
                    ACK: begin
                            busy <= 1;
                            // ACK after ADDRESS
                            if (ack_phase == 1'b0) begin
                            
                                if (negedge_tick) begin
                                    scl_drive <= 1;       
                                    sda_drive <= 0;      
                                end
                            
                                if (posedge_tick) begin
                                    scl_drive <= 0;       
                                   
                                    if (sda == 1'b0) begin
                                        ack_received <= 1'b1;
                                        ack_phase    <= 1'b1;
                                        bit_counter  <= 0;
                                        master_shift <= tx_data;
                                    end
                                    else begin
                                        ack_received <= 1'b0;
                                        ack_error    <= 1'b1;
                                       
                                    end
                                end
                            end
                           
                            // ACK after DATA
                            else begin
                                // WRITE: slave sends ACK
                                if (rw == 1'b0) begin
                                    if (negedge_tick) begin
                                        scl_drive <= 1;
                                        sda_drive <= 0;
                                    end
                                
                                    if (posedge_tick) begin
                                        scl_drive <= 0;
                                
                                        if (sda == 1'b0) begin
                                            ack_received <= 1'b1;
                                            
                                            // For multi-byte
                                            if (!last_byte) begin
                                                if (load_next) begin
                                                    master_shift <= tx_data;   // Load next byte
                                                    bit_counter  <= 0;         // Start counting bits again
                                                end
                                            end
                                            
                                        end
                                        else begin
                                            ack_received <= 1'b0;
                                            ack_error    <= 1'b1;
                                            ack_phase    <= 1'b0;
                                        end
                                    end
                                end
                           
                                // READ: master sends NACK
                                else begin
                                    if (negedge_tick) begin
                                        scl_drive <= 1;
                                        sda_drive <= 0;       
                                    end
                                
                                    if (posedge_tick) begin
                                        scl_drive    <= 0;
                                        ack_received <= 1'b1;
                                    end
                                end
                            end
                        end
                    
                    DATA: begin
                               busy <= 1;
                           
                               if (rw == 0) begin   // WRITE
                                   if (negedge_tick) begin
                                       scl_drive    <= 1;
                                       sda_drive    <= ~master_shift[DATA_WIDTH-1];
                                       master_shift <= master_shift << 1;
                                   end
                           
                                   if (posedge_tick) begin
                                       scl_drive   <= 0;
                                       bit_counter <= bit_counter + 1;
                                   end
                               end
                           
                               else begin   // READ
                                    sda_drive <= 0;
                                    if (negedge_tick)
                                        scl_drive <= 1;
    
                                    if (posedge_tick) begin
                                        scl_drive <= 0;
                                        rx_shift  <= {rx_shift[DATA_WIDTH-2:0], sda};
    
                                        if (bit_counter == DATA_WIDTH-1) begin
                                            rx_data <= {rx_shift[DATA_WIDTH-2:0], sda};
                                        end
                                            
                                        bit_counter <= bit_counter + 1;
                                    end
                               end
                           end
                               
                    STOP: begin
                               busy <= 1;
                               if (negedge_tick) begin
                                   scl_drive  <= 1;      
                                   sda_drive  <= 1;      
                                   stop_ready <= 1;
                               end
                           
                               if (posedge_tick && stop_ready) begin
                                   scl_drive  <= 0;      
                                   sda_drive  <= 0;      
                                   busy       <= 0;
                                   done       <= 1;
                                   stop_ready <= 0;
                               end
                           end
                   endcase
                end
            end                       
        end
        
    always @(*) begin
        next_state = current_state;
        
        case (current_state)
            IDLE: if (start && enable)
                    next_state = START;
                    
            START: next_state = ADDRESS;
            
            ADDRESS: if (bit_counter == ADDR_BITS)
                        next_state = ACK;
                        
            ACK: begin
                    if (posedge_tick) begin
                        if (ack_phase == 1'b0) begin
                            if (sda == 1'b0)
                                next_state = DATA;
                            else
                                next_state = STOP;
                        end
                        
                        else begin
                                if (sda == 1'b0) begin     
                                    if (last_byte)
                                        next_state = STOP;
                                    else if (load_next)
                                        next_state = DATA;
                                    else
                                        next_state = ACK;
                                    end
                                    
                                 else
                                    next_state = STOP;
                              end
                        end
                 end
            
            DATA: if (bit_counter == DATA_WIDTH)
                    next_state = ACK; // Because I2C needs ACK bit after evey 8 bit transfer
                    
            STOP: begin
                    if (posedge_tick && stop_ready)
                        next_state = IDLE;
                    else
                        next_state = STOP;
                  end
                  
            default:
                    next_state = IDLE;
        endcase
    end
endmodule
