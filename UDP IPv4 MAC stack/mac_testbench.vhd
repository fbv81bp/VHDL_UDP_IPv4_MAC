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

library WORK;
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

ENTITY stack_testbench IS
END stack_testbench;
 
ARCHITECTURE behavior OF stack_testbench IS 
 
    constant clock_period : time := 8 ns;
    signal clock : std_logic := '0';
    signal reset : std_logic := '1';
    signal rx_enable_i : std_logic := '0';
    signal rx_read_o : std_logic := '0';
    signal counter : std_logic_vector(7 downto 0) := x"00";
    signal frame_tx_tx_payload_o, mac_rx_tx_payload_o, ip_rx_tx_payload_o, udp_rx_tx_payload_o : std_logic_vector(7 downto 0);
    signal frame_tx_tx_enable_o, mac_rx_tx_enable_o, ip_rx_tx_enable_o, udp_rx_tx_enable_o : std_logic; 
    
    signal MAC_dest_address_o, MAC_source_address_o : std_logic_vector(47 downto 0);
    signal MAC_type_o : std_logic_vector(15 downto 0);
    signal MAC_frame_ready_o, MAC_frame_error_o : std_logic;

    signal IP_version_o :  STD_LOGIC_VECTOR (3 downto 0);
    signal IP_internet_header_length_o :  STD_LOGIC_VECTOR (3 downto 0);
    signal IP_differentiated_services_code_point_o :  STD_LOGIC_VECTOR (5 downto 0);
    signal IP_explicit_congestion_notification_o :  STD_LOGIC_VECTOR (1 downto 0);
    signal IP_total_length_o :  STD_LOGIC_VECTOR (15 downto 0);
    signal IP_identification_o :  STD_LOGIC_VECTOR (15 downto 0);
    signal IP_flags_o :  STD_LOGIC_VECTOR (2 downto 0);
    signal IP_fragment_offset_o :  STD_LOGIC_VECTOR(12 downto 0);
    signal IP_time_to_live_o :  STD_LOGIC_VECTOR (7 downto 0);
    signal IP_protocol_o :  STD_LOGIC_VECTOR (7 downto 0);
    signal IP_header_checksum_o :  STD_LOGIC_VECTOR (15 downto 0);
    signal IP_source_address_o :  STD_LOGIC_VECTOR (31 downto 0);
    signal IP_dest_address_o :  STD_LOGIC_VECTOR (31 downto 0);
    signal IP_frame_ready_o :  STD_LOGIC;
    signal IP_frame_error_o :  STD_LOGIC;   

    signal UDP_source_port_o :  STD_LOGIC_VECTOR(15 downto 0);
    signal UDP_dest_port_o :  STD_LOGIC_VECTOR(15 downto 0);
    signal UDP_length_o :  STD_LOGIC_VECTOR(15 downto 0);
    signal UDP_frame_ready_o :  STD_LOGIC;
    signal UDP_frame_error_o :  STD_LOGIC;

BEGIN

   -- Clock process definitions
   clock_process :process
   begin
        clock <= '0';
        wait for clock_period/2;
        clock <= '1';
        wait for clock_period/2;
   end process;
 

   -- Stimulus process
   stim_proc: process
   begin        
        reset <= '1';
        wait for clock_period*10;   
        reset <= '0';
        wait for clock_period;
        rx_enable_i <= '1';
        wait for clock_period*35;
        --rx_enable_i <= '0';
        wait;
   end process;

    process(clock)
    begin
        if rising_edge(clock) then
            if rx_read_o = '0' then
                counter <= x"00";
            else
                counter <= counter + '1';
            end if;
        end if;
    end process;
 
    -- Instantiate the Unit Under Test (UUT)
   uut_frame_tx: entity work.frame_tx PORT MAP (
        reset => reset,
        clock => clock,
        rx_payload_i => counter,
        rx_enable_i => rx_enable_i,
        rx_read_o => rx_read_o,
        tx_payload_o => frame_tx_tx_payload_o,
        tx_enable_o => frame_tx_tx_enable_o,
        MAC_dest_address => x"2CFDA1AD6EA8",
        MAC_source_address => x"DEADBEEF2019",
        MAC_type => x"0800",
        IP_version => x"4",
        IP_internet_header_length => x"5",
        IP_differentiated_services_code_point => "000000",
        IP_explicit_congestion_notification => "00",
        IP_total_length => x"00ff", --x"0100", --x"00fe", --x"00ff",
        IP_identification => x"0000",
        IP_flags => "000",
        IP_fragment_offset => "0"&x"000",
        IP_time_to_live => x"80",
        IP_protocol => x"11",
        IP_source_address => x"c0a8010f",
        IP_dest_address => x"c0a80102",
        UDP_source_port => x"abcd",
        UDP_dest_port => x"ef23",
        UDP_length => x"00eb"   
   );

    -- Instantiate the Unit Under Test (UUT)
   uut_mac_rx: entity work.mac_rx PORT MAP (
        reset,
        clock,
        frame_tx_tx_payload_o,
        frame_tx_tx_enable_o,
        mac_rx_tx_payload_o,
        mac_rx_tx_enable_o,
        
        --MAC specific parameters
        MAC_dest_address_o,
        MAC_source_address_o,
        MAC_type_o,
        
        --inter layer control signals
        MAC_frame_ready_o,
        MAC_frame_error_o);

   uut_ip_rx : entity work.ip_rx PORT MAP (
        reset,
        clock,
        mac_rx_tx_enable_o,
        mac_rx_tx_payload_o,
        ip_rx_tx_enable_o,
        ip_rx_tx_payload_o,
        
        --IP specific parameters
        IP_version_o,
        IP_internet_header_length_o,
        IP_differentiated_services_code_point_o,
        IP_explicit_congestion_notification_o,
        IP_total_length_o,
        IP_identification_o,
        IP_flags_o,
        IP_fragment_offset_o,
        IP_time_to_live_o,
        IP_protocol_o,
        IP_header_checksum_o,
        IP_source_address_o,
        IP_dest_address_o,
        
        --inter layer control signals
        IP_frame_ready_o,
        IP_frame_error_o);

inst_udp_rx : entity work.udp_rx PORT MAP (
        reset,
        clock,
        ip_rx_tx_enable_o,
        ip_rx_tx_payload_o,
        udp_rx_tx_enable_o,
        udp_rx_tx_payload_o,
        UDP_source_port_o,
        UDP_dest_port_o,
        UDP_length_o,
        UDP_frame_ready_o,
        UDP_frame_error_o);
 
END;
