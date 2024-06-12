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
        -- Pins are low-active because of the logic-level transistors
        -- pulling the line low when they are pulled high.
        board_row_data_in_n: out std_ulogic;
        board_shift_row_data_n: out std_ulogic;
        board_apply_new_row_n: out std_ulogic;
        board_row_strobe_in_n: out std_ulogic;
        board_shift_row_strobe_n: out std_ulogic;
        board_apply_new_row_strobe_n: out std_ulogic
    );
end entity;

architecture arch of board_driver is
    constant FRAMES_PER_SECOND: positive := 24;
    -- The board is being driven by multiplexing. The clock rate is composed by:
    --  1. Shifting in WIDTH-bits to feed in the line toggling srclk WIDTH times.
    --  2. Applying the current line by toggling rclk once.
    --  3. Shifting in new lines and applying them HEIGHT-times.
    --  4. We need to strobe the picture for at least 2^SAMPLE_DEPTH times to implement the grayscale bitdepth.
    --  5. Repeat 1-4. for FRAMES_PER_SECOND times.
    -- Note: The row strobe / line selection is hidden because we can shift it further when shifting in data.
    --       And we can apply it when we are applying the current line because it should be impercetible.
    constant BOARD_CLOCK_RATE: positive := (WIDTH + 1) * HEIGHT * (2 ** SAMPLE_DEPTH) * FRAMES_PER_SECOND;

    -- Defining an accuracy to achieve of 30 ms of cumulative skew over 4 minutes expressed in %.
    constant BOARD_CLOCK_ACCURACY: real := (0.030 / 240.0) * 100.0;

    -- We will set the board's signals based on the FPGA clock, but will
    -- calculate the target clock with a phase accumulator and set the pins when that target clock clocks.
    -- This way we don't need to additionally synchronize this module to the video driver and since
    -- we are not reading from the board, it's fine. We are setting the data lines on the falling edge
    -- and are clocking it into the board's shift registers on the rising edge.
    -- This half cycle should be enough time (maybe for some clocks it's not) to ignore any routing issues
    -- because we didn't constrain the outgoing signals to have equal skew.
    signal board_clock: std_ulogic;
    signal board_clock_last_states: std_ulogic_vector(1 downto 0);
    signal board_rising_edge, board_falling_edge: std_ulogic;
begin
    assert BOARD_CLOCK_RATE <= CLOCK_SPEED / 2
    report "board_driver: Calculated board clock rate of " & integer'image(BOARD_CLOCK_RATE) & " Hz is not achievable."
    severity failure;

    frame_buffer_request <= '0';
    frame_buffer_address <= (others => '0');
    -- frame_buffer_data;

    -- frame_available
    frame_processed <= '0';

    board_row_data_in_n <= '1';
    board_shift_row_data_n <= '1';
    board_apply_new_row_n <= '1';
    board_row_strobe_in_n <= '1';
    board_shift_row_strobe_n <= '1';
    board_apply_new_row_strobe_n <= '1';

    board_rising_edge <= '1' when board_clock_last_states = "01" else '0';
    board_falling_edge <= '1' when board_clock_last_states = "10" else '0';

    seq: process (clock) is
    begin
        if rising_edge(clock) then
            if reset = '1' then
                board_clock_last_states <= (others => '0');
            else
                board_clock_last_states <= board_clock_last_states(0) & board_clock;
            end if;
        end if;
    end process;

    phase_accumulator_inst: entity work.phase_accumulator
    generic map (
        SOURCE_CLOCK   => CLOCK_SPEED,
        TARGET_CLOCK   => BOARD_CLOCK_RATE,

        -- Accuracy is 30 ms cumulative skew over 4 minutes
        CLOCK_ACCURACY => BOARD_CLOCK_ACCURACY,

        MAX_BITWIDTH => 32,
        MAX_PRECISION => false
    )
    port map (
        clock     => clock,
        reset     => reset,

        clock_out => board_clock
    );
end architecture;
