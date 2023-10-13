-- Functional model of the onboard SPI flash (Macronix / Spansion)
-- This model only supports the basic READ command
-- For faster simulation try using smaller sizes

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

library work;
use work.sim_pkg.all;

entity spi_flash_model is
generic (
    SIZE: positive;
    INIT_FILE: string;
    INIT_VALUE: std_ulogic_vector(7 downto 0)
);
port (
    sclk: in std_ulogic;
    cs_n: in std_ulogic;

    sdi: in std_ulogic;
    sdo: out std_ulogic;

    wp: in std_ulogic;
    hold: in std_ulogic
);
end entity;

architecture functional of spi_flash_model is
    type memory_t is array (0 to SIZE-1) of std_ulogic_vector(7 downto 0);
    signal memory: memory_t := (others => INIT_VALUE);
begin
    init: process
        function byte_to_sulv (byte: in string(1 to 2)) return std_ulogic_vector is
            variable sulv: std_ulogic_vector(7 downto 0);
            variable nibble: integer;
        begin
            for i in 1 to 2 loop
                case byte(i) is
                    when '0' => nibble := 0;
                    when '1' => nibble := 1;
                    when '2' => nibble := 2;
                    when '3' => nibble := 3;
                    when '4' => nibble := 4;
                    when '5' => nibble := 5;
                    when '6' => nibble := 6;
                    when '7' => nibble := 7;
                    when '8' => nibble := 8;
                    when '9' => nibble := 9;
                    when 'A' => nibble := 10;
                    when 'B' => nibble := 11;
                    when 'C' => nibble := 12;
                    when 'D' => nibble := 13;
                    when 'E' => nibble := 14;
                    when 'F' => nibble := 15;
                    when others => report "spi_flash_model: Bad byte read: " & byte(i+1) severity failure;
                end case;

                sulv(4*(2-i)+3 downto 4*(2-i)+0) := std_ulogic_vector(to_unsigned(nibble, 4));
            end loop;

            return sulv;
        end function;

        procedure load_file is
            file memory_file: text;
            variable fos: file_open_status;

            variable current_line: line;
            variable current_address: integer := 0;
            
            variable byte: string(1 to 2);
            variable space: character;

            variable good: boolean;
        begin
            report "spi_flash_model: Loading init file: """ & INIT_FILE & """.";

            file_open(fos, memory_file, INIT_FILE, read_mode);
            assert fos = open_ok report "spi_flash_model: Loading init file failed: " & file_open_status'image(fos) & "." severity failure;

            while not endfile(memory_file) loop
                readline(memory_file, current_line);

                while current_line'length > 0 loop
                    if current_address = SIZE then
                        report "spi_flash_model: Init file is bigger than flash size. Aborting!" severity failure;
                    end if;

                    read(current_line, byte, good);
                    assert good report "spi_flash_model: Reading bad byte at: " & integer'image(current_address) & "." severity failure;

                    if current_line'length /= 0 then
                        read(current_line, space, good);
                        assert good and (space = ' ' or space = cr) report "spi_flash_model: Reading bad byte at: " & integer'image(current_address) & "." severity failure;
                    end if;

                    memory(current_address) <= byte_to_sulv(byte);
                    current_address := current_address + 1;
                end loop;
            end loop;

            report "spi_flash_model: Flash initialized with " & integer'image(current_address) & " bytes from init file.";
        end procedure;
    begin
        report "spi_flash_model: Initializing flash with size of " & integer'image(SIZE) & " bytes.";

        if INIT_FILE'length /= 0 then
            load_file;
        end if;

        wait;
    end process;
end architecture;
