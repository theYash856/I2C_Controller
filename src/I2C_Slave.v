`timescale 1ns / 1ps

module I2C_Slave #(
    parameter DATA_WIDTH = 8
)(
    input clk,
    input rst,
    input enable,
    input  [DATA_WIDTH-1:0] tx_data,
    input [6:0] slave_addr,
    inout sda,
    input scl,  // Slave doesn't drive scl unless clock stretching

    output reg [DATA_WIDTH-1:0] rx_data,
    output reg busy,
    output reg done,
    output reg addr_match
);

    // FSM States
    localparam IDLE      = 3'b000;
    localparam ADDRESS   = 3'b001;
    localparam ACK       = 3'b010;
    localparam DATA      = 3'b011;
    localparam STOP      = 3'b100;
    
    localparam ADDR_BITS   = 8;
    localparam COUNTER_MAX = (DATA_WIDTH > ADDR_BITS) ? DATA_WIDTH : ADDR_BITS;

    // Internal Registers
    reg [$clog2(COUNTER_MAX + 1)-1:0] bit_counter;
    reg [2:0] current_state, next_state;
    
    reg [DATA_WIDTH-1:0] tx_shift;  // Shifts data out during a READ transaction.
    reg [DATA_WIDTH-1:0] rx_shift;  // Shifts data in during a WRITE transaction.
    
    reg [7:0] addr_shift;    
    reg rw; 
    reg ack_phase;   
    
    reg sda_drive;
    assign sda = sda_drive ? 1'b0 : 1'bz;
    
    reg sda_prev; // Stores previous value of SDA
    reg scl_prev; // Stores previous value of SCL
    
    wire start_detect;
    assign start_detect = sda_prev && ~sda && scl; // To detect START state
    
    wire scl_rise;
    assign scl_rise = (~scl_prev) && scl; // Becomes high only when rising edge
    
    wire scl_fall;
    assign scl_fall = scl_prev && ~scl;   // Becomes high only when falling edge
    
    wire stop_detect;
    assign stop_detect = (~sda_prev) && sda && scl; // To detect STOP state
    
    // Sequential Block
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            bit_counter   <= 0;
            rx_data       <= 0;
            busy          <= 0;
            done          <= 0;
            addr_match    <= 0;
            tx_shift      <= 0;
            rx_shift      <= 0;
            addr_shift    <= 0;
            rw            <= 0;
            ack_phase     <= 0;
            sda_drive     <= 0;
            sda_prev      <= 1; 
            scl_prev      <= 1;
        end
        
        else begin
            sda_prev <= sda;
            scl_prev <= scl;
            
            if (!enable) begin
                    current_state <= IDLE;
                    busy          <= 0;
                    done          <= 0;
                    bit_counter   <= 0;
                    ack_phase     <= 0;
                    sda_drive     <= 0;
                    addr_match    <= 0;
                end
            
            // STOP can happen mid-transaction, so check it globally.
            else if (current_state != IDLE && stop_detect) begin
                    current_state  <= IDLE;
                    busy           <= 1'b0;
                    done           <= 1'b1;
                    sda_drive      <= 1'b0;
            end
            else begin
                current_state <= next_state;
                
                case(current_state) 
                    IDLE: begin
                            busy        <= 1'b0;
                            addr_match  <= 1'b0;
                            sda_drive   <= 1'b0;   
                            bit_counter <= 0;
                            ack_phase   <= 1'b0;
                          end
                    
                    ADDRESS: begin
                              busy <= 1'b1;
                              done <= 1'b0;
                          
                              if (scl_rise) begin
                                  addr_shift  <= {addr_shift[6:0], sda};
                                  bit_counter <= bit_counter + 1;
                              end
                          end
                    
                    ACK: begin
                              busy <= 1'b1;
                              // ACK after ADDRESS
                              if (!ack_phase) begin
                                  if (addr_shift[7:1] == slave_addr) begin
                                      addr_match <= 1'b1;
                                      rw <= addr_shift[0];
                          
                                      if (scl_fall) 
                                          sda_drive <= 1'b1;
                                          
                                  if (scl_rise) begin
                                          bit_counter <= 0;
                                          ack_phase   <= 1'b1;
                          
                                          if (addr_shift[0])
                                              tx_shift <= tx_data;
                                          else
                                              rx_shift <= 0;
                                      end
                                  end
                                  else begin
                                      addr_match <= 1'b0;
                                      sda_drive  <= 1'b0;
                                  end
                              end
                         
                              // ACK after DATA
                              else begin
                                  if (rw == 1'b0) begin
                                      // WRITE: slave drives ACK, released later
                                      if (scl_fall)
                                          sda_drive <= 1'b1;
                                          
                                      if (scl_rise)
                                          bit_counter <= 0;
                                  end
                                  else begin
                                      // READ: master drives ACK/NACK
                                      if (scl_fall)
                                          sda_drive <= 1'b0;

                                      if (scl_rise) begin
                                          bit_counter <= 0;
                                          if (sda == 1'b0)
                                              tx_shift <= tx_data;
                                      end
                                  end
                              end
                          end
                
                   DATA: begin
                            busy <= 1'b1;           
                            // Master WRITE        
                            if (rw == 1'b0) begin
                                if (scl_fall) 
                                    sda_drive <= 1'b0;
                                    
                                if (scl_rise) begin
                                    rx_shift    <= {rx_shift[DATA_WIDTH-2:0], sda};
                                    bit_counter <= bit_counter + 1;
                        
                                    if (bit_counter == DATA_WIDTH-1)
                                        rx_data <= {rx_shift[DATA_WIDTH-2:0], sda};
                                end
                            end
                            
                            // Master READ
                            else begin
                                if (scl_fall) begin
                                    sda_drive <= ~tx_shift[DATA_WIDTH-1];
                                    tx_shift  <= tx_shift << 1;
                                end
                            
                                if (scl_rise)
                                    bit_counter <= bit_counter + 1;
                            end      
                       end
                 
                 STOP: begin
                           busy <= 1'b1;
                           if (scl_fall)
                               sda_drive <= 1'b0;   // only release once SCL is actually low
                                                   
                           if (stop_detect) begin
                               busy <= 1'b0;
                               done <= 1'b1;
                           end
                       end      
                endcase
                end
            end
        end
        
    // Combinational next-state logic
    always @(*) begin
        next_state = current_state;
        
        if (current_state != IDLE && stop_detect) begin
              next_state = IDLE;
        end
        
        else begin
            case(current_state)
        
                IDLE:
                    if(enable && start_detect)
                        next_state = ADDRESS;
                        
                ADDRESS:
                    if(bit_counter == ADDR_BITS)
                        next_state = ACK;
        
                ACK: begin
                        if (scl_rise) begin
                        
                        // ACK after ADDRESS
                        if (!ack_phase) begin
                            if (addr_shift[7:1] == slave_addr)
                                next_state = DATA;
                            else
                                next_state = STOP;
                        end
                        
                        // ACK after DATA
                        else begin
                        
                            // Master WRITE
                            if (rw == 1'b0) begin
                                next_state = DATA;          // Wait for next byte until STOP
                            end
                        
                            // Master READ
                            else begin
                                if (sda == 1'b0)            // Master ACKed previous byte
                                    next_state = DATA;
                                else                        // Master NACKed previous byte
                                    next_state = STOP;
                                end
                            end
                        end
                    end
        
                DATA:
                    if(bit_counter == DATA_WIDTH)
                        next_state = ACK;
        
                STOP:
                    if(stop_detect)
                        next_state = IDLE;
            endcase
        end
    end
endmodule
