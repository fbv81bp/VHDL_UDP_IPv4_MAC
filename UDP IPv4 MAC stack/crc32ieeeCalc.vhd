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

entity crc32ieeeCalc is port(
            clock : in  STD_LOGIC;
            restart_crc : in STD_LOGIC;
            enable_crc : in STD_LOGIC;
            shift_crc : in STD_LOGIC;
            crc_data : in  STD_LOGIC_VECTOR (7 downto 0);
            crc_out : out  STD_LOGIC_VECTOR (7 downto 0));
end crc32ieeeCalc;

architecture Behavioral of crc32ieeeCalc is
    signal crc, nextCrc : std_logic_vector(31 downto 0);
    type crcArrayT is array (0 to 8) of std_logic_vector(31 downto 0);
    signal crcArray : crcArrayT;
begin
    
    process(clock)
    begin
        if rising_edge(clock) then
            if restart_crc = '1' then
                crc <= (others => '1');
            elsif enable_crc = '1' then
                crc <= nextCrc;
            elsif shift_crc = '1' then
                crc <= crc(23 downto 0) & x"00";
            end if;
        end if;
    end process;
    
    crcArray(0) <= crc;
    nextCrc <= crcArray(8);
    
    crc_gen : for i in 0 to 7 generate
    begin
        crcArray(i+1) <= (crcArray(i)(30 downto 0) & '0') when crcArray(i)(31) = crc_data(i) else
                         (crcArray(i)(30 downto 0) & '0') xor x"04C11DB7";
    end generate;
    
    out_gen : for j in 0 to 7 generate
    begin
        crc_out(j) <= not crc(31-j);
    end generate;

end Behavioral;
