-- Frame Buffer to be synthesized as BRAM.
-- One port can read/write (video_driver)
-- One port can only read (board_driver)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.log2;
use ieee.math_real.ceil;

entity frame_buffer is
    generic (
        WIDTH: positive;
        HEIGHT: positive
    );
    port (
        clock_a: in std_ulogic;
        address_a: in std_ulogic_vector(integer(ceil(log2(real(WIDTH * HEIGHT)))) - 1 downto 0);
        data_a: inout std_ulogic_vector(3 downto 0);
        write_enable_a: in std_ulogic;
        request_a: in std_ulogic;

        clock_b: in std_ulogic;
        address_b: in std_ulogic_vector(integer(ceil(log2(real(WIDTH * HEIGHT)))) - 1 downto 0);
        data_b: out std_ulogic_vector(3 downto 0);
        request_b: in std_ulogic
    );
end entity;

architecture arch of frame_buffer is
    type memory_t is array (0 to integer(ceil(log2(real(WIDTH * HEIGHT)))) - 1) of std_ulogic_vector(3 downto 0);
    signal memory: memory_t;
begin
    seq_port_a: process (clock_a)
    begin
        if rising_edge(clock_a) then
            data_a <= (others => '0');

            if request_a = '1' then
                if write_enable_a = '0' then
                    data_a <= memory(to_integer(unsigned(address_a)));
                else
                    memory(to_integer(unsigned(address_a))) <= data_a;
                end if;
            end if;
        end if;
    end process;

    seq_port_b: process (clock_b)
    begin
        if rising_edge(clock_b) then
            data_b <= (others => '0');

            if request_b = '1' then
                data_b <= memory(to_integer(unsigned(address_b)));
            end if;
        end if;
    end process;
end architecture;
