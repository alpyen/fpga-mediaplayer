library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.ceil;
use ieee.math_real.log2;

entity board_driver is
    generic (
        CLOCK_SPEED: positive;
        SAMPLE_DEPTH: positive;

        WIDTH: positive;
        HEIGHT: positive
    );
    port (
        clock: in std_ulogic;
        reset: in std_ulogic;

        frame_buffer_request: out std_ulogic;
        frame_buffer_address: out std_ulogic_vector(integer(ceil(log2(real(WIDTH * HEIGHT)))) - 1 downto 0);
        frame_buffer_data: in std_ulogic_vector(SAMPLE_DEPTH - 1 downto 0);

        frame_available: in std_ulogic;
        frame_processed: out std_ulogic;

        -- Board interface to LED Board
        board_row_data: out std_ulogic;
        board_shift_row_data: out std_ulogic;
        board_apply_row_and_strobe: out std_ulogic;
        board_row_strobe: out std_ulogic;
        board_shift_row_strobe: out std_ulogic;
        board_output_enable_n: out std_ulogic
    );
end entity;

architecture arch of board_driver is
    constant FRAMES_PER_SECOND: positive := 24;
    constant STROBES_PER_FRAME: positive := 4;

    -- The board is being driven by multiplexing. The clock rate is composed by:
    --   WIDTH * HEIGHT * BRIGHTNESS LEVELS * STROBES PER FRAME * FRAMES PER SECOND
    -- The actual clock rate is somewhat different due to the FSM transitions.
    -- Note: The clock rate can be reduced by merging some FSM states and transitions
    constant BOARD_CLOCK_RATE: positive := ((((WIDTH + 2) * HEIGHT + 1) * (2 ** SAMPLE_DEPTH - 1) + 1) * STROBES_PER_FRAME - 1) * FRAMES_PER_SECOND;

    -- Defining an accuracy to achieve of 30 ms of cumulative skew over 4 minutes.
    constant BOARD_CLOCK_ACCURACY: real := 0.030 / 240.0;

    type state_t is (ENTER_PREPARE, PREPARE, LEAVE_PREPARE, IDLE, FEED_ROW_DATA, FEED_ROW_SELECTION, APPLY_BOTH, CHECK_FOR_FRAME_DONE);
    signal state, state_next: state_t;

    -- We will set the board's signals based on the FPGA clock, but will
    -- calculate the target clock with a phase accumulator and set the pins when that target clock clocks.
    -- This way we don't need to additionally synchronize this module to the video driver and since
    -- we are not reading from the board, it's fine. We are setting the data lines on the falling edge
    -- and are clocking it into the board's shift registers on the rising edge.
    -- This half cycle should be enough time (maybe for some clocks it's not) to ignore any routing issues
    -- because we didn't constrain the outgoing signals to have equal skew.
    signal board_clock: std_ulogic;

    -- Contains the last few clock levels based upon the FPGA clock.
    -- This will be necessary to set the board signals based on its clock transitions.
    -- Our logic here will all work with the FPGA clock, but only switch on the board clock.
    signal board_clock_history: std_ulogic_vector(2 downto 0);

    signal board_row_data_int, board_row_data_int_next: std_ulogic;
    signal board_shift_row_data_int, board_shift_row_data_int_next: std_ulogic;
    signal board_apply_row_and_strobe_int, board_apply_row_and_strobe_int_next: std_ulogic;
    signal board_row_strobe_int, board_row_strobe_int_next: std_ulogic;
    signal board_shift_row_strobe_int, board_shift_row_strobe_int_next: std_ulogic;
    signal board_output_enable_n_int, board_output_enable_n_int_next: std_ulogic;

    signal frame_pixel_counter, frame_pixel_counter_next: unsigned(frame_buffer_address'range);
    signal pixel_x_counter, pixel_x_counter_next: unsigned(integer(ceil(log2(real(WIDTH)))) - 1 downto 0);
    signal pixel_y_counter, pixel_y_counter_next: unsigned(integer(ceil(log2(real(HEIGHT)))) - 1 downto 0);
    signal brightness_counter, brightness_counter_next: unsigned(SAMPLE_DEPTH - 1 downto 0);
    signal strobe_counter, strobe_counter_next: unsigned(integer(ceil(log2(real(STROBES_PER_FRAME + 1)))) - 1 downto 0);
begin
    assert BOARD_CLOCK_RATE <= CLOCK_SPEED / 2
    report "board_driver: Calculated board clock rate of " & integer'image(BOARD_CLOCK_RATE) & " Hz is not achievable."
    severity failure;

    board_row_data <= board_row_data_int;
    board_shift_row_data <= board_shift_row_data_int;
    board_apply_row_and_strobe <= board_apply_row_and_strobe_int;
    board_row_strobe <= board_row_strobe_int;
    board_shift_row_strobe <= board_shift_row_strobe_int;
    board_output_enable_n <= board_output_enable_n_int;

    seq: process (clock) is
    begin
        if rising_edge(clock) then
            if reset = '1' then
                state <= ENTER_PREPARE;
                board_clock_history <= (others => '0');

                board_row_data_int <= '0';
                board_shift_row_data_int <= '0';
                board_apply_row_and_strobe_int <= '0';
                board_row_strobe_int <= '0';
                board_shift_row_strobe_int <= '0';
                board_output_enable_n_int <= '1';

                frame_pixel_counter <= to_unsigned(0, frame_pixel_counter'length);
                pixel_x_counter <= to_unsigned(0, pixel_x_counter'length);
                pixel_y_counter <= to_unsigned(0, pixel_y_counter'length);
                brightness_counter <= to_unsigned(0, brightness_counter'length);
                strobe_counter <= to_unsigned(0, strobe_counter'length);
            else
                state <= state_next;
                board_clock_history <= board_clock_history(board_clock_history'left - 1 downto 0) & board_clock;

                board_row_data_int <= board_row_data_int_next;
                board_shift_row_data_int <= board_shift_row_data_int_next;
                board_apply_row_and_strobe_int <= board_apply_row_and_strobe_int_next;
                board_row_strobe_int <= board_row_strobe_int_next;
                board_shift_row_strobe_int <= board_shift_row_strobe_int_next;
                board_output_enable_n_int <= board_output_enable_n_int_next;

                frame_pixel_counter <= frame_pixel_counter_next;
                pixel_x_counter <= pixel_x_counter_next;
                pixel_y_counter <= pixel_y_counter_next;
                brightness_counter <= brightness_counter_next;
                strobe_counter <= strobe_counter_next;
            end if;
        end if;
    end process;

    comb: process (
        state, board_clock_history,
        frame_buffer_data, frame_available, frame_pixel_counter,
        pixel_x_counter, pixel_y_counter, brightness_counter, strobe_counter,
        board_row_data_int, board_shift_row_data_int, board_apply_row_and_strobe_int,
        board_row_strobe_int, board_shift_row_strobe_int, board_output_enable_n_int
    ) is
    begin
        state_next <= state;

        frame_pixel_counter_next <= frame_pixel_counter;
        pixel_x_counter_next <= pixel_x_counter;
        pixel_y_counter_next <= pixel_y_counter;
        brightness_counter_next <= brightness_counter;
        strobe_counter_next <= strobe_counter;

        board_row_data_int_next <= board_row_data_int;
        board_shift_row_data_int_next <= board_shift_row_data_int;
        board_apply_row_and_strobe_int_next <= board_apply_row_and_strobe_int;
        board_row_strobe_int_next <= board_row_strobe_int;
        board_shift_row_strobe_int_next <= board_shift_row_strobe_int;
        board_output_enable_n_int_next <= board_output_enable_n_int;

        frame_buffer_request <= '0';
        frame_buffer_address <= (others => '0');
        frame_processed <= '0';

        case state is
            when ENTER_PREPARE =>
                if board_clock_history = "111" then
                    state_next <= PREPARE;
                end if;

            -- Since the board powers up in a random state we need to make sure,
            -- it doesn't light up randomly before the FPGA is connected.
            -- So we pulled up the high-side switches to put them normally off
            -- but we need to clear the shift registers before enabling their output
            -- because we secured that also with a pull up on the Output Enable line.
            when PREPARE =>
                case board_clock_history is
                    when "110" =>
                        board_row_strobe_int_next <= '1';
                        board_shift_row_strobe_int_next <= '0';

                    when "001" =>
                        board_shift_row_strobe_int_next <= '1';
                        pixel_y_counter_next <= pixel_y_counter + 1;

                        if pixel_y_counter = HEIGHT - 1 then
                            state_next <= LEAVE_PREPARE;
                        end if;

                    when others => null;
                end case;

            when LEAVE_PREPARE =>
                if board_clock_history = "001" then
                    state_next <= IDLE;
                    board_apply_row_and_strobe_int_next <= '1';
                    board_output_enable_n_int_next <= '0';
                end if;

            when IDLE =>
                if frame_available = '1' and board_clock_history = "111" then
                    state_next <= FEED_ROW_DATA;

                    frame_pixel_counter_next <= to_unsigned(0, frame_pixel_counter'length);
                    pixel_x_counter_next <= to_unsigned(0, pixel_x_counter'length);
                    pixel_y_counter_next <= to_unsigned(0, pixel_y_counter'length);
                    brightness_counter_next <= to_unsigned(0, brightness_counter'length);
                    strobe_counter_next <= to_unsigned(0, strobe_counter'length);
                end if;

            when FEED_ROW_DATA =>
                case board_clock_history is
                    when "110" =>
                        frame_buffer_request <= '1';
                        frame_buffer_address <= std_ulogic_vector(frame_pixel_counter);
                        frame_pixel_counter_next <= frame_pixel_counter + 1;

                        board_shift_row_data_int_next <= '0';

                    when "100" =>
                        if unsigned(frame_buffer_data) > brightness_counter then
                            board_row_data_int_next <= '1';
                        else
                            board_row_data_int_next <= '0';
                        end if;

                    when "001" =>
                        board_shift_row_data_int_next <= '1';
                        pixel_x_counter_next <= pixel_x_counter + 1;

                        if pixel_x_counter = WIDTH - 1 then
                            state_next <= FEED_ROW_SELECTION;
                        end if;

                    when others => null;
                end case;

            when FEED_ROW_SELECTION =>
                case board_clock_history is
                    when "110" =>
                        -- Row Selection shift registers have to output a zero
                        -- to select a line because they are driving P-channel MOSFETS!
                        -- That's why the logic is inverted compared to the row data
                        -- and we only strobe one '0' through there because we only
                        -- want one line selected to time-multiplex the display.
                        if pixel_y_counter = 0 then
                            board_row_strobe_int_next <= '0';
                        else
                            board_row_strobe_int_next <= '1';
                        end if;

                        board_shift_row_strobe_int_next <= '0';

                    when "001" =>
                        state_next <= APPLY_BOTH;
                        board_shift_row_strobe_int_next <= '1';

                        board_apply_row_and_strobe_int_next <= '0';

                    when others => null;
                end case;

            when APPLY_BOTH =>
                if board_clock_history = "001" then
                    state_next <= FEED_ROW_DATA;
                    board_apply_row_and_strobe_int_next <= '1';
                    pixel_x_counter_next <= to_unsigned(0, pixel_x_counter'length);
                    pixel_y_counter_next <= pixel_y_counter + 1;

                    if pixel_y_counter = HEIGHT - 1 then
                        state_next <= CHECK_FOR_FRAME_DONE;
                    end if;
                end if;

            when CHECK_FOR_FRAME_DONE =>
                if board_clock_history = "111" then
                    state_next <= FEED_ROW_DATA;
                    frame_pixel_counter_next <= to_unsigned(0, frame_pixel_counter'length);
                    pixel_x_counter_next <= to_unsigned(0, pixel_x_counter'length);
                    pixel_y_counter_next <= to_unsigned(0, pixel_y_counter'length);
                    brightness_counter_next <= brightness_counter + 1;

                    -- The brightness counter should not run from 0 to 15, but from 0 to 14.
                    -- That is because all comparisons in FEED_ROW_DATA will not trigger for the last case (15).
                    -- Meaning that we are not achieving maximum brightness this way.
                    if brightness_counter = 2 ** SAMPLE_DEPTH - 1 - 1 then
                        brightness_counter_next <= to_unsigned(0, brightness_counter'length);
                        strobe_counter_next <= strobe_counter + 1;

                        if strobe_counter = STROBES_PER_FRAME - 1 then
                            state_next <= IDLE;
                            frame_processed <= '1';
                        end if;
                    end if;
                end if;
        end case;
    end process;

    phase_accumulator_inst: entity work.phase_accumulator
    generic map (
        SOURCE_CLOCK   => CLOCK_SPEED,
        TARGET_CLOCK   => BOARD_CLOCK_RATE,

        CLOCK_ACCURACY => BOARD_CLOCK_ACCURACY,

        MAX_BITWIDTH   => 32,
        MAX_PRECISION  => false
    )
    port map (
        clock     => clock,
        reset     => reset,

        clock_out => board_clock
    );
end architecture;
