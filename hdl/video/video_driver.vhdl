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

    type state_t is (IDLE, DECODE, WAIT_UNTIL_PREVIOUS_FRAME_PLAYED);
    signal state, state_next: state_t;
    signal decoding_start, decoding_done: std_ulogic;

    type decoder_state_t is (IDLE, BIT_0, BIT_1, BIT_2, NEW_SAMPLE, READ_OLD_PIXEL, WRITE_NEW_PIXEL);
    signal decoder_state, decoder_state_next: decoder_state_t;

    signal first_frame, first_frame_next: std_ulogic;

    type pixel_difference_t is (UNCHANGED, UP, DOWN, REPLACE);
    signal pixel_difference, pixel_difference_next: pixel_difference_t;

    -- Signals controlled from video driver
    signal request_0_a, request_1_a: std_ulogic;
    signal write_enable_0_a, write_enable_1_a: std_ulogic;
    signal address_a: std_ulogic_vector(integer(ceil(log2(real(WIDTH * HEIGHT)))) - 1 downto 0);
    signal data_0_a_in, data_1_a_in: std_ulogic_vector(SAMPLE_DEPTH - 1 downto 0);
    signal data_0_a_out, data_1_a_out: std_ulogic_vector(data_0_a_in'range);

    -- Necessary for tracking where we are.
    --  frame_pixel_counter tracks which pixel of the current frame is being processed [0, WIDTH * HEIGHT - 1]
    --  new_pixel_value holds the actual new pixel value if the old pixel is to be replaced [0, 2 ^ SAMPLE_DEPTH - 1]
    --  pixel_bit_counter tracks the current bit position that is being read in for new_pixel_value [0, SAMPLE_DEPTH - 1]
    signal frame_pixel_counter, frame_pixel_counter_next: unsigned(address_a'range);
    signal new_pixel_value, new_pixel_value_next: unsigned(data_0_a_in'range);
    signal pixel_bit_counter, pixel_bit_counter_next: unsigned(new_pixel_value'range);

    -- Signals controlled from board driver
    signal request_0_b, request_1_b: std_ulogic;
    signal address_b: std_ulogic_vector(address_a'range);
    signal data_0_b_out, data_1_b_out: std_ulogic_vector(data_0_a_in'range);

    -- Determines which buffer the video driver is currently filling/filled.
    -- The board driver is operating meanwhile on the other buffer.
    signal selected_buffer, selected_buffer_next: std_ulogic;

    signal board_driver_request: std_ulogic;
    signal board_driver_address: std_ulogic_vector(address_b'range);
    signal board_driver_data: std_ulogic_vector(data_0_b_out'range);

    signal board_driver_frame_available, board_driver_frame_available_next: std_ulogic;
    signal board_driver_frame_processed: std_ulogic;
begin
    seq: process (clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                state <= IDLE;
                decoder_state <= IDLE;

                first_frame <= '1';

                frame_pixel_counter <= to_unsigned(0, frame_pixel_counter'length);
                pixel_difference <= UNCHANGED;
                new_pixel_value <= to_unsigned(0, new_pixel_value'length);
                pixel_bit_counter <= to_unsigned(0, pixel_bit_counter'length);

                selected_buffer <= '0';
                board_driver_frame_available <= '0';
            else
                state <= state_next;
                decoder_state <= decoder_state_next;

                first_frame <= first_frame_next;

                frame_pixel_counter <= frame_pixel_counter_next;
                pixel_difference <= pixel_difference_next;
                new_pixel_value <= new_pixel_value_next;
                pixel_bit_counter <= pixel_bit_counter_next;

                selected_buffer <= selected_buffer_next;
                board_driver_frame_available <= board_driver_frame_available_next;
            end if;
        end if;
    end process;

    comb: process (
        state, selected_buffer, decoding_done, board_driver_frame_processed,
        video_driver_play, video_fifo_empty, first_frame
    )
    begin
        state_next <= state;
        selected_buffer_next <= selected_buffer;

        decoding_start <= '0';
        video_driver_done <= '0';

        first_frame_next <= first_frame;

        case (state) is
            when IDLE =>
                video_driver_done <= '1';
                first_frame_next <= '1';

                if video_driver_play = '1' and video_fifo_empty /= '1' then
                    state_next <= DECODE;
                end if;

            when DECODE =>
                if decoding_done = '1' then
                    if first_frame = '0' then
                        state_next <= WAIT_UNTIL_PREVIOUS_FRAME_PLAYED;
                    else
                        first_frame_next <= '0';
                        decoding_start <= '1';
                    end if;
                else
                    if video_fifo_empty /= '1' then
                        decoding_start <= '1';
                    else
                        if video_driver_play = '0' then
                            state_next <= IDLE;
                        end if;
                    end if;
                end if;

            when WAIT_UNTIL_PREVIOUS_FRAME_PLAYED =>
                if board_driver_frame_processed = '1' then
                    state_next <= DECODE;
                    selected_buffer_next <= not selected_buffer;
                end if;
        end case;
    end process;

    decoder_fsm: process (
        decoder_state, decoding_start, video_fifo_data_out, video_fifo_empty,
        frame_pixel_counter, pixel_difference, new_pixel_value, pixel_bit_counter,
        data_0_a_out, data_1_a_out, board_driver_frame_available, selected_buffer,
        first_frame
    )
    begin
        decoder_state_next <= decoder_state;
        decoding_done <= '0';

        video_fifo_read_enable <= '0';
        board_driver_frame_available_next <= board_driver_frame_available;

        frame_pixel_counter_next <= frame_pixel_counter;
        pixel_difference_next <= pixel_difference;
        new_pixel_value_next <= new_pixel_value;
        pixel_bit_counter_next <= to_unsigned(0, pixel_bit_counter'length);

        request_0_a <= '0';
        write_enable_0_a <= '0';
        data_0_a_in <= (others => '0');

        request_1_a <= '0';
        write_enable_1_a <= '0';
        data_1_a_in <= (others => '0');

        address_a <= (others => '0');

        -- The video fifo is being fed fast enough and has enough of a buffer
        -- to never read it empty when a full frame is available.
        -- However, since we are padding the video bits to full bytes it can happen
        -- that there are remaining bits in the fifo that need to be flushed.
        -- The way we have to do it is by jumping back to IDLE when there
        -- is no data to be read from the fifo. Even though the fifos are being
        -- fed fast enough (they have to, otherwise we cannot hit the target framerate)
        -- we should still check if video_driver_play is asserted to see
        -- if there is actually any data to be pushed into the fifo from the control driver's side.

        case decoder_state is
            when IDLE =>
                if decoding_start = '1' then
                    decoder_state_next <= BIT_0;
                    video_fifo_read_enable <= '1';
                    frame_pixel_counter_next <= to_unsigned(0, frame_pixel_counter'length);
                    board_driver_frame_available_next <= '0';
                end if;

            when BIT_0 =>
                if video_fifo_data_out(0) = '0' then
                    decoder_state_next <= READ_OLD_PIXEL;
                    pixel_difference_next <= UNCHANGED;
                else
                    decoder_state_next <= BIT_1;
                    video_fifo_read_enable <= '1';
                end if;

            when BIT_1 =>
                if video_fifo_data_out(0) = '0' then
                    decoder_state_next <= READ_OLD_PIXEL;
                    pixel_difference_next <= UP;
                else
                    decoder_state_next <= BIT_2;
                    video_fifo_read_enable <= '1';
                end if;

            when BIT_2 =>
                if video_fifo_data_out(0) = '0' then
                    decoder_state_next <= READ_OLD_PIXEL;
                    pixel_difference_next <= DOWN;
                else
                    decoder_state_next <= NEW_SAMPLE;
                    video_fifo_read_enable <= '1';
                end if;

            when NEW_SAMPLE =>
                new_pixel_value_next <= new_pixel_value(new_pixel_value'left - 1 downto 0) & video_fifo_data_out(0);
                pixel_bit_counter_next <= pixel_bit_counter + 1;

                if pixel_bit_counter = SAMPLE_DEPTH - 1 then
                    decoder_state_next <= WRITE_NEW_PIXEL;
                    pixel_difference_next <= REPLACE;
                else
                    video_fifo_read_enable <= '1';
                end if;

            when READ_OLD_PIXEL =>
                decoder_state_next <= WRITE_NEW_PIXEL;

                -- We don't want to read the previous frame's buffer for the first frame
                -- because it will corrupt the whole playback when it's not full of zeroes.
                -- This will happen if we playback two videos end the first one
                -- does not end with a completely dark frame.
                if first_frame /= '1' then
                    address_a <= std_ulogic_vector(frame_pixel_counter);

                    if selected_buffer = '0' then
                        request_0_a <= '1';
                    else
                        request_1_a <= '1';
                    end if;
                end if;

            when WRITE_NEW_PIXEL =>
                frame_pixel_counter_next <= frame_pixel_counter + 1;
                address_a <= std_ulogic_vector(frame_pixel_counter);

                if first_frame = '1' then
                    if selected_buffer = '0' then
                        request_0_a <= '1';
                        write_enable_0_a <= '1';

                        case pixel_difference is
                            when UNCHANGED => data_0_a_in <= std_ulogic_vector(to_unsigned(0, data_0_a_in'length));
                            when UP => data_0_a_in <= std_ulogic_vector(to_unsigned(0, data_0_a_in'length) + 1);
                            when DOWN => data_0_a_in <= std_ulogic_vector(to_unsigned(0, data_0_a_in'length) - 1);
                            when REPLACE => data_0_a_in <= std_ulogic_vector(new_pixel_value);
                        end case;
                    else
                        request_1_a <= '1';
                        write_enable_1_a <= '1';

                        case pixel_difference is
                            when UNCHANGED => data_1_a_in <= std_ulogic_vector(to_unsigned(0, data_1_a_in'length));
                            when UP => data_1_a_in <= std_ulogic_vector(to_unsigned(0, data_1_a_in'length) + 1);
                            when DOWN => data_1_a_in <= std_ulogic_vector(to_unsigned(0, data_1_a_in'length) - 1);
                            when REPLACE => data_1_a_in <= std_ulogic_vector(new_pixel_value);
                        end case;
                    end if;
                else
                    if selected_buffer = '0' then
                        request_1_a <= '1';
                        write_enable_1_a <= '1';

                        case pixel_difference is
                            when UNCHANGED => data_1_a_in <= data_0_a_out;
                            when UP => data_1_a_in <= std_ulogic_vector(unsigned(data_0_a_out) + 1);
                            when DOWN => data_1_a_in <= std_ulogic_vector(unsigned(data_0_a_out) - 1);
                            when REPLACE => data_1_a_in <= std_ulogic_vector(new_pixel_value);
                        end case;
                    else
                        request_0_a <= '1';
                        write_enable_0_a <= '1';

                        case pixel_difference is
                            when UNCHANGED => data_0_a_in <= data_1_a_out;
                            when UP => data_0_a_in <= std_ulogic_vector(unsigned(data_1_a_out) + 1);
                            when DOWN => data_0_a_in <= std_ulogic_vector(unsigned(data_1_a_out) - 1);
                            when REPLACE => data_0_a_in <= std_ulogic_vector(new_pixel_value);
                        end case;
                    end if;
                end if;

                if frame_pixel_counter = WIDTH * HEIGHT - 1 then
                    decoder_state_next <= IDLE;
                    decoding_done <= '1';
                    board_driver_frame_available_next <= '1';
                else
                    decoder_state_next <= BIT_0;
                    video_fifo_read_enable <= '1';
                end if;
        end case;
    end process;

    request_0_b <= board_driver_request when selected_buffer = '0' else '0';
    request_1_b <= board_driver_request when selected_buffer = '1' else '0';
    address_b <= board_driver_address;
    board_driver_data <= data_0_b_out or data_1_b_out;

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
        data_a_in      => data_0_a_in,
        data_a_out     => data_0_a_out,
        write_enable_a => write_enable_0_a,
        request_a      => request_0_a,

        address_b      => address_b,
        data_b_out     => data_0_b_out,
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
        data_a_in      => data_1_a_in,
        data_a_out     => data_1_a_out,
        write_enable_a => write_enable_1_a,
        request_a      => request_1_a,

        address_b      => address_b,
        data_b_out     => data_1_b_out,
        request_b      => request_1_b
    );
end architecture;
