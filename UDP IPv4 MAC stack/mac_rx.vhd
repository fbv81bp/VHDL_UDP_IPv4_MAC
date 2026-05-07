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


--0 clock cycle: load regs 0
--1 clock cycle: load regs 1
--2 clock cycle: rx_payload(2), rx_enable(2) are loaded
--3 clock cycle: crc_out is valid
--4 clock cycle: all comparisons are valid
--5 clock cycle: state machine has jumped with respect to comparisons


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

entity mac_rx is
    Port ( reset : in STD_LOGIC;
           clock : in STD_LOGIC;
           rx_payload_i : in STD_LOGIC_VECTOR (7 downto 0);
           rx_enable_i : in STD_LOGIC;
           tx_payload_o : out STD_LOGIC_VECTOR (7 downto 0);
           tx_enable_o : out STD_LOGIC;
           
           --MAC specific parameters
           MAC_dest_address_o : out STD_LOGIC_VECTOR (47 downto 0);
           MAC_source_address_o : out STD_LOGIC_VECTOR (47 downto 0);
           MAC_type_o : out STD_LOGIC_VECTOR (15 downto 0);
           
           --inter layer control signals
           MAC_frame_ready_o : out STD_LOGIC;
           MAC_frame_error_o : out STD_LOGIC);
end mac_rx;

architecture Behavioral of mac_rx is

    component crc32ieeeCheck is port(
        clock : in  STD_LOGIC;
        restart_crc : in STD_LOGIC;
        enable_crc : in STD_LOGIC;
        crc_data : in  STD_LOGIC_VECTOR (7 downto 0);
        crc_out : out  STD_LOGIC_VECTOR (31 downto 0));
    end component;

    type rx_payloadT is array (8 downto 0) of std_logic_vector(7 downto 0);
    signal rx_payload : rx_payloadT;
    signal rx_enable : std_logic_vector(8 downto 0);
    signal crc_start_cmp, sof_cmp, crc_cmp : std_logic;
    signal header_cnt : std_logic;
    type stateT is (WAIT_SOF, HEADER, PAYLOAD, CRC);
    signal state : stateT;
    signal counter : std_logic_vector(11 downto 0);   
    signal shifter : std_logic_vector(111 downto 0);
    constant sof : std_logic_vector(7 downto 0) := x"d5";
    signal restart_crc, enable_crc : std_logic;
    signal crc_data : std_logic_vector(7 downto 0);
    signal crc_out : std_logic_vector(31 downto 0);

begin

    process(reset, clock)
    begin
        if reset = '1' then
            rx_payload(0)   <= (others => '0');
            rx_payload(1)   <= (others => '0');
            rx_payload(2)   <= (others => '0');
            rx_payload(3)   <= (others => '0');
            rx_payload(4)   <= (others => '0');
            rx_payload(5)   <= (others => '0');
            rx_payload(6)   <= (others => '0');
            rx_payload(7)   <= (others => '0');
            rx_payload(8)   <= (others => '0');
            rx_enable       <= (others => '0');
            
            sof_cmp         <= '0';
            crc_cmp         <= '0';
            crc_start_cmp   <= '0';
            
            header_cnt      <= '0';

            restart_crc     <= '1';
            enable_crc      <= '0';
            
            state           <= WAIT_SOF;
            counter         <= (others => '0');
            shifter         <= (others => '0');

            tx_enable_o         <= '0';
            tx_payload_o        <= (others => '0');
            MAC_frame_ready_o   <= '0';
            MAC_frame_error_o   <= '0';
        
        elsif rising_edge(clock) then
--data and enable pipeline
            rx_payload <= rx_payload(7 downto 0) & rx_payload_i;
            rx_enable <= rx_enable(7 downto 0) & rx_enable_i;
--1 cycle early comparations of pipeline data
            if rx_payload(4) = sof then
                crc_start_cmp <= '1';
            else
                crc_start_cmp <= '0';
            end if;
            if rx_payload(7) = sof then
                sof_cmp <= '1';
            else
                sof_cmp <= '0';
            end if;
            if state = CRC then
                crc_cmp <= '0';
            elsif rx_enable(2 downto 1) = "10" then
                if crc_out = rx_payload(2) & rx_payload(3) & rx_payload(4) & rx_payload(5) then
                    crc_cmp <= '1';
                end if;
            end if;
--1 cycle early comparation of state counter
            if counter = x"00c" then
                header_cnt <= '1';
            else
                header_cnt <= '0';
            end if;
--begin state machine
            case state is
--wait for start of frame
                when WAIT_SOF => 
                    if rx_enable(5) = '1' then
                        if crc_start_cmp = '1' then
                            enable_crc <= '1';
                            restart_crc <= '0';
                        end if;
                    end if;
                    if rx_enable(8) = '1' then
                        if sof_cmp = '1' then
                            state <= HEADER;
                        end if;
                    end if;
                    MAC_frame_ready_o <= '0';            
                    MAC_frame_error_o <= '0';           
                    counter <= x"000";
--receive header
                when HEADER =>
                    if rx_enable(8) = '1' then
                        if header_cnt = '1' then
                            state <= PAYLOAD;
                            counter <= x"000";
                        else
                            counter <= counter + '1';
                        end if;
                        shifter <= shifter(103 downto 0) & rx_payload(8);
                    else
                        state <= WAIT_SOF;
                        MAC_frame_error_o <= '1';           
                        counter <= x"000";
                    end if;
--receive and transmit payload
                when PAYLOAD =>
--                    if rx_enable(0) = '0' then
--                        enable_crc <= '0';
--                    end if;
                    if rx_enable(4) = '0' then
                        state <= CRC;
                        counter <= x"000";
                        tx_enable_o <= '0';
                    else
                        tx_payload_o <= rx_payload(8);
                        tx_enable_o <= '1';
                    end if;
--check CRC
                when others => --CRC
                    if crc_cmp = '1' then
                        MAC_frame_ready_o <= '1';
                    else
                        MAC_frame_error_o <= '1';           
                    end if;
                    state <= WAIT_SOF;
                    restart_crc <= '1';
                    enable_crc <= '0';
--end of state machine
            end case;
        end if;
     end process;

    crc_data <= rx_payload(5);
    crc_inst : crc32ieeeCheck port map (
                clock,
                restart_crc,
                enable_crc,
                crc_data,
                crc_out);
                
    MAC_dest_address_o   <= shifter(111 downto 64);
    MAC_source_address_o <= shifter(63 downto 16);
    MAC_type_o <= shifter(15  downto  0);

end Behavioral;
