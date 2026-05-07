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


entity frame_tx is
    Port ( 
           reset : in STD_LOGIC;
           clock : in STD_LOGIC;
           rx_payload_i : in STD_LOGIC_VECTOR (7 downto 0);
           rx_enable_i : in STD_LOGIC;
           rx_read_o : out STD_LOGIC;
           tx_payload_o : out STD_LOGIC_VECTOR (7 downto 0);
           tx_enable_o : out STD_LOGIC;
           
           --MAC specific parameters
           MAC_dest_address : in STD_LOGIC_VECTOR (47 downto 0);
           MAC_source_address : in STD_LOGIC_VECTOR (47 downto 0);
           MAC_type : in STD_LOGIC_VECTOR (15 downto 0);

           --IP specific parameters
           IP_version : in STD_LOGIC_VECTOR (3 downto 0);
           IP_internet_header_length : in STD_LOGIC_VECTOR (3 downto 0);
           IP_differentiated_services_code_point : in STD_LOGIC_VECTOR (5 downto 0);
           IP_explicit_congestion_notification : in STD_LOGIC_VECTOR (1 downto 0);
           IP_total_length : in STD_LOGIC_VECTOR (15 downto 0);
           IP_identification : in STD_LOGIC_VECTOR (15 downto 0);
           IP_flags : in STD_LOGIC_VECTOR (2 downto 0);
           IP_fragment_offset : in STD_LOGIC_VECTOR(12 downto 0);
           IP_time_to_live : in STD_LOGIC_VECTOR (7 downto 0);
           IP_protocol : in STD_LOGIC_VECTOR (7 downto 0);
           IP_source_address : in STD_LOGIC_VECTOR (31 downto 0);
           IP_dest_address : in STD_LOGIC_VECTOR (31 downto 0);
           
           --UDP specific parameters
           UDP_source_port : in STD_LOGIC_VECTOR(15 downto 0);
           UDP_dest_port : in STD_LOGIC_VECTOR(15 downto 0);
           UDP_length : in STD_LOGIC_VECTOR(15 downto 0));
end frame_tx;

architecture Behavioral of frame_tx is

    component crc32ieeeCalc is port(
       clock : in  STD_LOGIC;
       restart_crc : in STD_LOGIC;
       enable_crc : in STD_LOGIC;
       shift_crc : in STD_LOGIC;
       crc_data : in  STD_LOGIC_VECTOR (7 downto 0);
       crc_out : out  STD_LOGIC_VECTOR (7 downto 0));
    end component;

    constant preamble : std_logic_vector(7 downto 0) := x"55";
    constant start_of_frame : std_logic_vector(7 downto 0) := x"d5";
    constant payload_length : std_logic_vector(11 downto 0) := x"0e3"; --change to shorter for simulation
    
    type state_type is (IDLE, PRE_SOF, HEADER, PAYLOAD, CRC, INTERFRAME);
    signal state : state_type;
    signal counter : std_logic_vector(11 downto 0);
    signal shifter : std_logic_vector(399 downto 0);
    signal tx_payload1, tx_payload0 : std_logic_vector(7 downto 0);
    signal tx_enable1, tx_enable0 : std_logic;
    signal pre_sof_cmp, header_cmp, payload_cmp, crc_cmp, interframe_cmp : std_logic;
    signal restart_crc, enable_crc, shift_crc : std_logic;
    signal crc_data : std_logic_vector(7 downto 0);
    signal crc_out : std_logic_vector(7 downto 0);
    signal shift_crc_reg : std_logic;
    signal IP_header_checksum, checksum1 : std_logic_vector(15 downto 0);
    signal checksum0 : std_logic_vector(31 downto 0);
begin
    checksum0 <=  (x"0000" & (IP_version & IP_internet_header_length & IP_differentiated_services_code_point & IP_explicit_congestion_notification))
                + (x"0000" & IP_total_length)
                + (x"0000" & IP_identification)
                + (x"0000" & (IP_flags & IP_fragment_offset))
                + (x"0000" & (IP_time_to_live & IP_protocol))
                + (x"0000" & IP_source_address(31 downto 16))
                + (x"0000" & IP_source_address(15 downto 0))
                + (x"0000" & IP_dest_address(31 downto 16))
                + (x"0000" & IP_dest_address(15 downto 0));
    checksum1 <= checksum0(31 downto 16) + checksum0(15 downto 0);
    IP_header_checksum  <= NOT std_logic_vector(checksum1);

    process(clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                state <= IDLE;
                counter <= x"000";
                     rx_read_o <= '0';
                     tx_enable0 <= '0';
                     tx_enable1 <= '0';
                     payload_cmp <= '0';
                     pre_sof_cmp <= '0';
                     header_cmp <= '0';
                     crc_cmp <= '0';
                     interframe_cmp <= '0';
                     restart_crc <= '1';
                     enable_crc <= '0';
                     shift_crc <= '0';
                     tx_payload0 <= x"00";
                     tx_payload1 <= x"00";
                     shift_crc_reg <= '0';
            else
                if counter = x"006" then
                    pre_sof_cmp <= '1';
                else
                    pre_sof_cmp <= '0';
                end if;
                if counter = x"028" then
                   header_cmp <= '1';
                else
                   header_cmp <= '0';
                end if;
              if counter = payload_length then 
                    payload_cmp <= '1';
                else
                    payload_cmp <= '0';
                end if;
                if counter = x"002" then
                   crc_cmp <= '1';
                else
                   crc_cmp <= '0';
                end if;
                if counter = x"00a" then
                   interframe_cmp <= '1';
                else
                   interframe_cmp <= '0';
                end if;
--begin state machine
                case state is
--load shift register
                    when IDLE =>
                        if rx_enable_i = '1' then
                            state <= PRE_SOF;
                            counter <= x"000";
                            shifter <=  preamble & preamble & preamble & preamble & preamble & preamble & preamble
                                        & start_of_frame 
                                        
                                        & MAC_dest_address
                                        & MAC_source_address
                                        & MAC_type
                                        
                                        & IP_version
                                        & IP_internet_header_length
                                        & IP_differentiated_services_code_point
                                        & IP_explicit_congestion_notification
                                        & IP_total_length
                                        & IP_identification
                                        & IP_flags
                                        & IP_fragment_offset
                                        & IP_time_to_live 
                                        & IP_protocol
                                        & IP_header_checksum
                                        & IP_source_address
                                        & IP_dest_address
                                        
                                        & UDP_source_port
                                        & UDP_dest_port
                                        & UDP_length
                                        & x"ecec"; --error check
                        end if;
                        restart_crc <= '1';
                        rx_read_o <= '0';
                        tx_enable0 <= '0';
                        tx_payload0 <= x"00";
--shift out preamble and start of frame
                    when PRE_SOF =>
                        if pre_sof_cmp = '1' then
                            state <= HEADER;
                            counter <= x"000";
                        else
                            counter <= counter + '1';
                            tx_enable0 <= '1';
                        end if;
                        tx_payload0 <= shifter(399 downto 392);
                        shifter <= shifter(391 downto 0) & x"eb";
--shift out header
                    when HEADER =>
                        if header_cmp = '1' then
                            state <= PAYLOAD;
                            counter <= x"002"; -- for the exactt calculationn of payload
                            rx_read_o <= '1';
                        else
                            counter <= counter + '1';
                        end if;
                        restart_crc <= '0';
                        enable_crc <= '1';                        
                        tx_payload0 <= shifter(399 downto 392);
                        shifter <= shifter(391 downto 0) & x"eb";
--forward payload, fill with "empty frame" byte if useful payload is over
                    when PAYLOAD =>
                        if payload_cmp = '1' then
                            rx_read_o <= '0';
                            state <= CRC;
                            counter <= x"000";
                        else
                            counter <= counter + '1';
                        end if;
                        if rx_enable_i = '1' then
                            tx_payload0 <= rx_payload_i;
                        else
                            tx_payload0 <= x"ef"; --filling byte in case there is no input (ef stands for  End of Frame)
                        end if;
--shift out CRC calculated during the previous two states
                    when CRC =>
                        if crc_cmp = '1' then
                            state <= INTERFRAME;
                            counter  <= x"000";
                        else
                            counter <= counter + '1';
                            enable_crc <= '0';
                            shift_crc <= '1';                                    
                        end if;
                        tx_payload0 <= x"00";
--signal 12 bytes of interframe gap
                    when others => --INTERFRAME
                        if interframe_cmp = '1' then
                            state <= IDLE;
                            counter  <= x"000";
                        else
                            counter <= counter + '1';
                        end if;
                        tx_enable0 <= '0';
                        shift_crc <= '0';
                        restart_crc <= '1';
                        tx_payload0 <= x"00";
--end of state machine
                end case;
            end if;
            tx_payload1 <= tx_payload0;
            tx_enable1 <= tx_enable0;
            shift_crc_reg <= shift_crc;
        end if;
    end process;

crc_data <= tx_payload0;

crc_inst : crc32ieeeCalc port map (
            clock,
            restart_crc,
            enable_crc,
            shift_crc_reg,
            crc_data,
            crc_out);

tx_payload_o <= crc_out when shift_crc_reg = '1' else tx_payload1;
tx_enable_o <= tx_enable1;

end Behavioral;
