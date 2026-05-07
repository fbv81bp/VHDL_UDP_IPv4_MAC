--MIT License
--
--Copyright (c) 2019 Balazs Valer Fekete fbv81bp@[gmail.com|outlook.hu]
--
--Permission is hereby granted, free of charge, to any person obtaining a copy
--of this software and associated documentation files (the "Software"), to deal
--in the Software without restriction, including without limitation the rights
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--copies of the Software, and to permit persons to whom the Software is
--furnished to do so, subject to the following conditions:
--
--The above copyright notice and this permission notice shall be included in all
--copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--SOFTWARE.


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

entity udp_rx is
    Port ( reset : in STD_LOGIC;
           clock : in STD_LOGIC;
           rx_enable_i : in STD_LOGIC;
           rx_payload_i : in STD_LOGIC_VECTOR (7 downto 0);
           tx_enable_o : out STD_LOGIC;
           tx_payload_o : out STD_LOGIC_VECTOR (7 downto 0);

           --UDP specific parameters
           UDP_source_port_o : out STD_LOGIC_VECTOR(15 downto 0);
           UDP_dest_port_o : out STD_LOGIC_VECTOR(15 downto 0);
           UDP_length_o : out STD_LOGIC_VECTOR(15 downto 0);
           
           --inter layer control signals
           UDP_frame_ready_o : out STD_LOGIC;
           UDP_frame_error_o : out STD_LOGIC);
end udp_rx;

architecture Behavioral of udp_rx is

    --type rx_payloadT is array (1 downto 0) of std_logic_vector(7 downto 0);
    signal rx_payload : std_logic_vector(7 downto 0);--rx_payloadT;
    signal rx_enable : std_logic;--_vector(1 downto 0);
    signal header_cnt, payload_cnt : std_logic;
    type stateT is (HEADER, PAYLOAD, DROP);
    signal state : stateT;
    signal counter : std_logic_vector(11 downto 0);   
    signal shifter : std_logic_vector(63 downto 0);
    signal total_length : std_logic_vector(11 downto 0);

begin

    process(reset, clock)
    begin
        if reset = '1' then
            rx_payload   <= (others => '0');
            --rx_payload(1)   <= (others => '0');
            rx_enable       <= '0';--(others => '0');

            header_cnt <= '0';
            payload_cnt <= '0';

            state           <= HEADER;
            counter         <= (others => '0');
            shifter         <= (others => '0');

            tx_enable_o        <= '0';
            tx_payload_o       <= (others => '0');
            UDP_frame_ready_o   <= '0';
            UDP_frame_error_o   <= '0';
        
        elsif rising_edge(clock) then
--registering data and enable
            rx_payload <= rx_payload_i;
            rx_enable <= rx_enable_i;
--1 cycle early comparations of state counter
            if counter = x"006" then
                header_cnt <= '1';
            else
                header_cnt <= '0';
            end if;
            if counter = total_length - "10" then
                payload_cnt <= '1';
            else
                payload_cnt <= '0';
            end if;
--begin state machine
            case state is
--receive header
                when HEADER =>
                    if rx_enable = '1' then
                        if header_cnt = '1' then
                            state <= PAYLOAD;
                            --IP_frame_error_o <= '1'; --ez itt valszeg nem kell, mert el sem kezdõdött az adás
                        end if;
                    shifter <= shifter (55 downto 0) & rx_payload;
                    counter <= counter + '1';
                    else
                        counter <= (others => '0');
                    end if;
                    tx_enable_o <= '0';
                    tx_payload_o <= x"eb";
                    UDP_frame_ready_o <= '0';
                    UDP_frame_error_o <= '0';
--receive and transmit payload
                when others => --PAYLOAD
                    if rx_enable = '1' then
                        if payload_cnt = '1' then
                            state <= HEADER;
                            UDP_frame_ready_o <= '1';
                        end if;
                        tx_enable_o <= '1';
                        tx_payload_o <= rx_payload;
                        counter <= counter + '1';
                    else
                        state <= HEADER; --incoming IP frame shorter than expected UDP frame
                        UDP_frame_error_o <= '1';
                        --assert false report "shorter" severity warning;
                    end if;
             end case;
        end if;
    end process;

    total_length <= shifter(27 downto 16); --only handling UDP frames that fit into a MAC frame, not 64k long ones
                                    
    UDP_source_port_o <= shifter(63 downto 48);
    UDP_dest_port_o <= shifter(47 downto 32);
    UDP_length_o <= shifter(31 downto 16);

end Behavioral;
