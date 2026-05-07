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

entity ip_rx is
    Port ( reset : in STD_LOGIC;
           clock : in STD_LOGIC;
           rx_enable_i : in STD_LOGIC;
           rx_payload_i : in STD_LOGIC_VECTOR (7 downto 0);
           tx_enable_o : out STD_LOGIC;
           tx_payload_o : out STD_LOGIC_VECTOR (7 downto 0);

           --IP specific parameters
           IP_version_o : out STD_LOGIC_VECTOR (3 downto 0);
           IP_internet_header_length_o : out STD_LOGIC_VECTOR (3 downto 0);
           IP_differentiated_services_code_point_o : out STD_LOGIC_VECTOR (5 downto 0);
           IP_explicit_congestion_notification_o : out STD_LOGIC_VECTOR (1 downto 0);
           IP_total_length_o : out STD_LOGIC_VECTOR (15 downto 0);
           IP_identification_o : out STD_LOGIC_VECTOR (15 downto 0);
           IP_flags_o : out STD_LOGIC_VECTOR (2 downto 0);
           IP_fragment_offset_o : out STD_LOGIC_VECTOR(12 downto 0);
           IP_time_to_live_o : out STD_LOGIC_VECTOR (7 downto 0);
           IP_protocol_o : out STD_LOGIC_VECTOR (7 downto 0);
           IP_header_checksum_o : out STD_LOGIC_VECTOR (15 downto 0);
           IP_source_address_o : out STD_LOGIC_VECTOR (31 downto 0);
           IP_dest_address_o : out STD_LOGIC_VECTOR (31 downto 0);

           --inter layer control signals
           IP_frame_ready_o : out STD_LOGIC;
           IP_frame_error_o : out STD_LOGIC);
end ip_rx;

architecture Behavioral of ip_rx is

    type rx_payloadT is array (1 downto 0) of std_logic_vector(7 downto 0);
    signal rx_payload : rx_payloadT;
    signal rx_enable : std_logic_vector(1 downto 0);
    signal vhl_cmp : std_logic;
    signal header_cnt, payload_cnt : std_logic;
    type stateT is (IDLE, HEADER, PAYLOAD, DROP);
    signal state : stateT;
    signal counter : std_logic_vector(11 downto 0);   
    signal shifter : std_logic_vector(159 downto 0);
    constant version_and_header_length : std_logic_vector(7 downto 0) := x"45";
    signal total_length : std_logic_vector(11 downto 0);
    
begin

    process(reset, clock)
    begin
        if reset = '1' then
            rx_payload(0)   <= (others => '0');
            rx_payload(1)   <= (others => '0');
            rx_enable       <= (others => '0');

            vhl_cmp <= '0';

            header_cnt <= '0';
            payload_cnt <= '0';

            state           <= IDLE;
            counter         <= (others => '0');
            shifter         <= (others => '0');

            tx_enable_o        <= '0';
            tx_payload_o       <= (others => '0');
            IP_frame_ready_o   <= '0';
            IP_frame_error_o   <= '0';
        
        elsif rising_edge(clock) then
--data and enable pipeline
            rx_payload <= rx_payload(0) & rx_payload_i;
            rx_enable <= rx_enable(0) & rx_enable_i;
--1 cycle early comparations of pipeline data
            if rx_payload(0) = version_and_header_length then
                vhl_cmp <= '1';
            else
                vhl_cmp <= '0';
            end if;
--1 cycle early comparations of state counter
            if counter = x"012" then
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
--wait for transmission to start and check first byte
                when IDLE =>
                    if rx_enable(1) = '1' then
                        if vhl_cmp = '1' then --handling only minimum length IPv4 headers
                            state <= HEADER;
                            shifter <= shifter (151 downto 0) & rx_payload(1);
                            counter <= counter + '1';
                        else
                            state <= DROP;
                            --IP_frame_error_o <= '1'; --ez itt valszeg nem kell, mert el sem kezdõdött az adás
                        end if;
                    else
                        counter <= (others => '0');
                        IP_frame_ready_o <= '0';
                        IP_frame_error_o <= '0';
                    end if;
                    tx_enable_o <= '0';
                    tx_payload_o <= x"eb";
--receive header
                when HEADER =>
                    if rx_enable(1) = '1' then
                        if header_cnt = '1' then
                            state <= PAYLOAD;
                        end if;
                        shifter <= shifter (151 downto 0) & rx_payload(1);
                        counter <= counter + '1';
                    else --frame ended abruptly
                        state <= DROP;
                        --IP_frame_error_o <= '1'; --ez itt valszeg nem kell, mert el sem kezdõdött az adás
                    end if;
                    --tx_enable_o <= '0';
                    --tx_payload_o <= x"eb";
--receive and transmit payload
                when PAYLOAD =>
                    if rx_enable(1) = '1' then
                        if payload_cnt = '1' then
                            if rx_enable(0) = '0' then
                                state <= IDLE;
                                IP_frame_ready_o <= '1';
                            else
                                state <= DROP; --incoming MAC frame longer than expected IP frame
-- EZ HIBA!!! MI VAN HA PADDINGES VOLT A MAC?!?!!?                                
                                IP_frame_error_o <= '1';
                                assert false report "longer" severity warning;
                            end if;
                        end if;
                        tx_enable_o <= '1';
                        tx_payload_o <= rx_payload(1);
                        counter <= counter + '1';
                    else
                        state <= DROP; --incoming MAC frame shorter than expected IP frame
                        IP_frame_error_o <= '1';
                        assert false report "shorter" severity warning;
                    end if;
                when others => --DROP
                    if rx_enable(1) = '0' then
                        state <= IDLE;
                    end if;
                    tx_enable_o <= '0';
                    tx_payload_o <= x"eb";
                    IP_frame_error_o <= '0';
                    counter <= (others => '0');
            end case;
        end if;
    end process;

    total_length <= shifter(139 downto 128); --only handling IP frames that fit into a MAC frame, not 64k long ones
                                    
    IP_version_o <= shifter(159 downto 156);
    IP_internet_header_length_o <= shifter(155 downto 152);
    IP_differentiated_services_code_point_o <= shifter(151 downto 146);
    IP_explicit_congestion_notification_o <= shifter(145 downto 144);
    IP_total_length_o <= shifter(143 downto 128);
    IP_identification_o  <= shifter(127 downto 112);
    IP_flags_o <= shifter(111 downto 109);
    IP_fragment_offset_o <= shifter(108 downto 96);
    IP_time_to_live_o <= shifter(95 downto 88);
    IP_protocol_o <= shifter(87 downto 80);
    IP_header_checksum_o <= shifter(79 downto 64); 
    IP_source_address_o <= shifter(63 downto 32);
    IP_dest_address_o <= shifter(31 downto 0);
    
end Behavioral;
