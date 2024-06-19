-- Frame Buffer to be synthesized as on-chip BRAM.
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
    -- The memory type we are targeting here is BRAM, we could explicitly set the ram_style attribute,
    -- but instead of doing that, we can just design our buffer so that it will map to it naturally.
    -- This also means that we cannot reset the memory contents, but that is not necessary anyway.
    -- Also we need to stick to the coding guidelines in order for the tool to automatically infer memory blocks.
    -- This way we don't need to instantiate vendor-specific macros and most synthesis tools can understand it.
    type memory_t is array (0 to WIDTH * HEIGHT - 1) of std_ulogic_vector(SAMPLE_DEPTH - 1 downto 0);
    shared variable memory: memory_t := (others => (others => '0'));
begin

    -- Separate both ports into different processes so the synthesis tool can infer dual port memory.
    seq_a: process (clock)
    begin
        if rising_edge(clock) then
            data_a_out <= (others => '0');

            if reset /= '1' then
                if request_a = '1' then
                    if write_enable_a = '0' then
                        data_a_out <= memory(to_integer(unsigned(address_a)));
                    else
                        memory(to_integer(unsigned(address_a))) := data_a_in;
                    end if;
                end if;
            end if;
        end if;
    end process;

    seq_b: process (clock)
    begin
        if rising_edge(clock) then
            data_b_out <= (others => '0');

            if reset /= '1' then
                if request_b = '1' then
                    data_b_out <= memory(to_integer(unsigned(address_b)));
                end if;
            end if;
        end if;
    end process;
end architecture;
