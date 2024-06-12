library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.log2;
use ieee.math_real.ceil;

entity video_driver is
    generic (
        CLOCK_SPEED: positive;
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

    -- Signals controlled from video driver
    signal request_0_a, request_1_a: std_ulogic;
    signal write_enable_0_a, write_enable_1_a: std_ulogic;
    signal address_a: std_ulogic_vector(integer(ceil(log2(real(WIDTH * HEIGHT)))) - 1 downto 0);
    signal data_0_a, data_1_a: std_logic_vector(SAMPLE_DEPTH - 1 downto 0);

    -- Signals controlled from board driver
    signal request_0_b, request_1_b: std_ulogic;
    signal address_b: std_ulogic_vector(address_a'range);
    signal data_0_b, data_1_b: std_ulogic_vector(data_0_a'range);

    -- Determines which buffer the video driver is currently filling/filled.
    -- The board driver is operating meanwhile on the other buffer.
    signal selected_buffer, selected_buffer_next: std_ulogic;

    signal board_driver_request: std_ulogic;
    signal board_driver_address: std_ulogic_vector(address_a'range);
    signal board_driver_data: std_ulogic_vector(data_0_a'range);
    signal board_driver_processed: std_ulogic;

    signal board_driver_frame_available: std_ulogic;
    signal board_driver_frame_processed: std_ulogic;
begin
    video_driver_done <= '1';

    address_a <= (others => '0');
    write_enable_0_a <= '0';
    request_0_a <= '0';
    write_enable_1_a <= '0';
    request_1_a <= '0';

    selected_buffer <= '0';
    selected_buffer_next <= '0';

    board_driver_frame_available <= '0';

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

    board_driver_inst: entity work.board_driver
    generic map (
        CLOCK_SPEED  => CLOCK_SPEED,
        SAMPLE_DEPTH => SAMPLE_DEPTH,
        WIDTH        => WIDTH,
        HEIGHT       => HEIGHT
    )
    port map (
        clock                        => clock,
        reset                        => reset,

        frame_buffer_request         => board_driver_request,
        frame_buffer_address         => board_driver_address,
        frame_buffer_data            => board_driver_data,

        frame_available              => board_driver_frame_available,
        frame_processed              => board_driver_frame_processed,

        board_row_data_in_n          => board_row_data_in_n,
        board_shift_row_data_n       => board_shift_row_data_n,
        board_apply_new_row_n        => board_apply_new_row_n,
        board_row_strobe_in_n        => board_row_strobe_in_n,
        board_shift_row_strobe_n     => board_shift_row_strobe_n,
        board_apply_new_row_strobe_n => board_apply_new_row_strobe_n
    );

    request_0_b <= board_driver_request when selected_buffer = '0' else '0';
    request_1_b <= board_driver_request when selected_buffer = '1' else '0';
    address_b <= board_driver_address;
    board_driver_data <= data_0_b or data_1_b;

    frame_buffer_0: entity work.frame_buffer
    generic map (
        SAMPLE_DEPTH => SAMPLE_DEPTH,
        WIDTH  => WIDTH,
        HEIGHT => HEIGHT
    )
    port map (
        clock          => clock,
        reset          => reset,

        address_a      => address_a,
        data_a         => data_0_a,
        write_enable_a => write_enable_0_a,
        request_a      => request_0_a,

        address_b      => address_b,
        data_b         => data_0_b,
        request_b      => request_0_b
    );

    frame_buffer_1: entity work.frame_buffer
    generic map (
        SAMPLE_DEPTH => SAMPLE_DEPTH,
        WIDTH  => WIDTH,
        HEIGHT => HEIGHT
    )
    port map (
        clock          => clock,
        reset          => reset,

        address_a      => address_a,
        data_a         => data_1_a,
        write_enable_a => write_enable_1_a,
        request_a      => request_1_a,

        address_b      => address_b,
        data_b         => data_1_b,
        request_b      => request_1_b
    );
end architecture;
