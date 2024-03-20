library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.log2;
use ieee.math_real.ceil;

entity video_driver is
    generic (
        CLOCK_SPEED: positive;
        BOARD_CLOCK_SPEED: positive;
        WIDTH: positive;
        HEIGHT: positive
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

    -- TODO: Use data_a for a0 and a1 signals and logic not ulogic
    --       Frame buffer must put it to 'Z' not '0' anymore

    -- Signals controlled from video driver
    signal address_a: std_ulogic_vector(integer(ceil(log2(real(WIDTH * HEIGHT)))) - 1 downto 0);
    signal data_a_0, data_a_1: std_logic_vector(SAMPLE_DEPTH - 1 downto 0);
    signal write_enable_a_0, write_enable_a_1: std_ulogic;
    signal request_a_0, request_a_1: std_ulogic;

    -- Signals controlled from board driver
    signal address_b: std_ulogic_vector(address_a'range);
    signal data_b, data_b_0, data_b_1: std_ulogic_vector(data_a_0'range);
    signal request_b_0, request_b_1: std_ulogic;

    -- Determines which buffer the video driver is currently filling/filled.
    -- The board driver is operating meanwhile on the other buffer.
    signal selected_buffer, selected_buffer_next: std_ulogic;

    -- NOTE: Board Driver: Set signals on falling edge and clock them in on the rising edge.
    --                     This will be necessary since it's a fabric clock and the signals
    --                     are nowhere near synchronous or properly aligned outside the chip.
begin
    video_driver_done <= '1';

    -- video_fifo_read_enable <= '0';

    board_row_data_in_n <= '1';
    board_shift_row_data_n <= '1';
    board_apply_new_row_n <= '1';
    board_row_strobe_in_n <= '1';
    board_shift_row_strobe_n <= '1';
    board_apply_new_row_strobe_n <= '1';

    address_a <= (others => '0');
    write_enable_a_0 <= '0';
    data_a_0 <= (others => 'Z');
    request_a_0 <= '0';
    write_enable_a_1 <= '0';
    data_a_1 <= (others => 'Z');
    request_a_1 <= '0';

    address_b <= (others => '0');
    request_b_0 <= '0';
    request_b_1 <= '0';

    selected_buffer <= '0';
    selected_buffer_next <= '0';

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

    frame_buffer_0: entity work.frame_buffer
    generic map (
        SAMPLE_DEPTH => 4,
        WIDTH  => WIDTH,
        HEIGHT => HEIGHT
    )
    port map (
        clock_a        => clock,
        address_a      => address_a,
        data_a         => data_a_0,
        write_enable_a => write_enable_a_0,
        request_a      => request_a_0,
        clock_b        => board_clock,
        address_b      => address_b,
        data_b         => data_b_0,
        request_b      => request_b_0
    );

    data_b <= data_b_0 or data_b_1;

    frame_buffer_1: entity work.frame_buffer
    generic map (
        SAMPLE_DEPTH => 4,
        WIDTH  => WIDTH,
        HEIGHT => HEIGHT
    )
    port map (
        clock_a        => clock,
        address_a      => address_a,
        data_a         => data_a_1,
        write_enable_a => write_enable_a_1,
        request_a      => request_a_1,
        clock_b        => board_clock,
        address_b      => address_b,
        data_b         => data_b_1,
        request_b      => request_b_1
    );
end architecture;
