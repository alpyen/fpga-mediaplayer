-- Frame Buffer to be synthesized as on-chip RAM.
-- One port can read/write (video_driver)
-- One port can only read (board_driver)

-- Port data_a is split into two separate ports because
-- using it as inout with std_logic will cause combinational loops
-- which will not implement safely (even though they may be fine).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.log2;
use ieee.math_real.ceil;

entity frame_buffer is
    generic (
        SAMPLE_DEPTH: positive;
        WIDTH: positive;
        HEIGHT: positive
    );
    port (
        clock: in std_ulogic;
        reset: in std_ulogic;

        -- Port A (R/W)
        address_a: in std_ulogic_vector(integer(ceil(log2(real(WIDTH * HEIGHT)))) - 1 downto 0);
        data_a_in: in std_ulogic_vector(SAMPLE_DEPTH - 1 downto 0);
        data_a_out: out std_ulogic_vector(SAMPLE_DEPTH - 1 downto 0);
        write_enable_a: in std_ulogic;
        request_a: in std_ulogic;

        -- Port B (Ro)
        address_b: in std_ulogic_vector(integer(ceil(log2(real(WIDTH * HEIGHT)))) - 1 downto 0);
        data_b_out: out std_ulogic_vector(SAMPLE_DEPTH - 1 downto 0);
        request_b: in std_ulogic
    );
end entity;

architecture arch of frame_buffer is
    type memory_t is array (0 to WIDTH * HEIGHT - 1) of std_ulogic_vector(SAMPLE_DEPTH - 1 downto 0);
    signal memory, memory_next: memory_t := (others => (others => '0'));

    signal data_a_out_next: std_ulogic_vector(data_a_out'range);
    signal data_b_out_next: std_ulogic_vector(data_b_out'range);
begin
    seq: process (clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                memory <= (others => (others => '0'));

                data_a_out <= (others => '0');
                data_b_out <= (others => '0');
            else
                memory <= memory_next;

                data_a_out <= data_a_out_next;
                data_b_out <= data_b_out_next;
            end if;
        end if;
    end process;

    comb: process (memory, request_a, write_enable_a, address_a, data_a_in, request_b, address_b) is
    begin
        memory_next <= memory;

        data_a_out_next <= (others => '0');
        data_b_out_next <= (others => '0');

        if request_a = '1' then
            if write_enable_a = '0' then
                data_a_out_next <= memory(to_integer(unsigned(address_a)));
            else
                memory_next(to_integer(unsigned(address_a))) <= data_a_in;
            end if;
        end if;

        if request_b = '1' then
            data_b_out_next <= memory(to_integer(unsigned(address_b)));
        end if;
    end process;
end architecture;
