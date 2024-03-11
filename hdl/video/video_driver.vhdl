library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.log2;
use ieee.math_real.ceil;

entity video_driver is
    generic (
        CLOCK_SPEED: positive;
        BOARD_CLOCK_SPEED: positive
    );
    port (
        clock: in std_ulogic;
        reset: in std_ulogic;

        -- Video Driver Interface
        video_driver_play: in std_ulogic;
        video_driver_done: out std_ulogic;

        -- Video Fifo
        video_fifo_read_enable: out std_ulogic;
        video_fifo_data_out: in std_ulogic_vector(0 downto 0);
        video_fifo_empty: in std_ulogic;

        -- Board interface to LED Board
        -- Pins are low-active because of the logic-level transistors
        -- pulling the line low when they are pulled high.
        board_clock: in std_ulogic;
        board_row_data_in_n: out std_ulogic;
        board_shift_row_data_n: out std_ulogic;
        board_apply_new_row_n: out std_ulogic;
        board_row_strobe_in_n: out std_ulogic;
        board_shift_row_strobe_n: out std_ulogic;
        board_apply_new_row_strobe_n: out std_ulogic
    );
end entity;

architecture arch of video_driver is
    constant SAMPLE_DEPTH: positive := 4;

    -- NOTE: Don't forget to implement the logic on the falling edge!
begin
    video_driver_done <= '1';

    -- video_fifo_read_enable <= '0';

    board_row_data_in_n <= '1';
    board_shift_row_data_n <= '1';
    board_apply_new_row_n <= '1';
    board_row_strobe_in_n <= '1';
    board_shift_row_strobe_n <= '1';
    board_apply_new_row_strobe_n <= '1';

    process (clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                video_fifo_read_enable <= '0';
            else
                video_fifo_read_enable <= '0';

                if video_fifo_empty /= '1' and video_driver_play = '1' then
                    video_fifo_read_enable <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture;
