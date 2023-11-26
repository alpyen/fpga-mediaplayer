library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.log2;
use ieee.math_real.ceil;

entity audio_driver is
    port (
        clock: in std_logic;
        reset: in std_ulogic;

        -- Audio Driver Interface
        audio_driver_start: in std_ulogic;

        -- Audio Fifo
        audio_fifo_read_enable: out std_ulogic;
        audio_fifo_data_out: in std_ulogic_vector(0 downto 0);
        audio_fifo_empty: in std_ulogic
    );
end entity;

architecture arch of audio_driver is
    type state_t is (IDLE, DECODE, WAIT_UNTIL_SAMPLE_PLAYED);
    signal state, state_next: state_t;

    type decode_state_t is (IDLE, BIT_0, BIT_1, BIT_2, NEW_SAMPLE);
    signal decode_state, decode_state_next: decode_state_t;

    signal decoding_start: std_ulogic;
    signal decoding_done: std_ulogic;

    -- This constant is here to not use magic numbers.
    -- The audio driver is "optimized" to work on four bit samples.
    -- It might work with higher bits, but you'd need to make sure
    -- the Fifos don't run dry.
    -- The encoding of 0/+1/-1 doesn't make much sense with higher bit depths
    -- since the jumps are mostly wider than 0/+1/-1.
    constant SAMPLE_DEPTH: positive := 4;

    signal sample, sample_next: signed(SAMPLE_DEPTH - 1 downto 0);

    signal sample_bit_counter, sample_bit_counter_next: unsigned(integer(ceil(log2(real(SAMPLE_DEPTH)))) - 1 downto 0);
begin
    seq: process (clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                state <= IDLE;

                decode_state <= IDLE;

                sample <= to_signed(0, sample'length);
                sample_bit_counter <= to_unsigned(0, sample_bit_counter'length);
            else
                state <= state_next;

                decode_state <= decode_state_next;

                sample <= sample_next;
                sample_bit_counter <= sample_bit_counter_next;
            end if;
        end if;
    end process;

    fsm: process (state, audio_driver_start, audio_fifo_empty, decoding_done)
    begin
        state_next <= state;

        decoding_start <= '0';

        case state is
            when IDLE =>
                if audio_driver_start = '1' then
                    state_next <= DECODE;
                end if;

            when DECODE =>
                if decoding_done = '1' then
                    state_next <= WAIT_UNTIL_SAMPLE_PLAYED;
                else
                    if audio_fifo_empty = '0' then
                        decoding_start <= '1';
                    else
                        state_next <= IDLE;
                    end if;
                end if;

            when WAIT_UNTIL_SAMPLE_PLAYED =>
                state_next <= DECODE;
                -- assert false report "Audio Driver: WAIT_UNTIL_SAMPLE_PLAYED reached." severity failure;
        end case;
    end process;

    decode_fsm: process (decode_state, decoding_start, audio_fifo_data_out, sample, sample_bit_counter)
    begin
        decode_state_next <= decode_state;

        audio_fifo_read_enable <= '0';

        decoding_done <= '0';

        sample_next <= sample;
        sample_bit_counter_next <= to_unsigned(0, sample_bit_counter'length);

        case decode_state is
            when IDLE =>
                if decoding_start = '1' then
                    decode_state_next <= BIT_0;
                    audio_fifo_read_enable <= '1';
                end if;

            when BIT_0 =>
                -- Note that the Fifo output is a 1 bit vector.

                -- 0 ~> new sample = previous sample
                if audio_fifo_data_out(0) = '0' then
                    decode_state_next <= IDLE;
                    decoding_done <= '1';
                    -- sample_next <= sample;
                else
                    decode_state_next <= BIT_1;
                    audio_fifo_read_enable <= '1';
                end if;

            when BIT_1 =>
                -- 1 0 ~> new sample = previous sample + 1
                if audio_fifo_data_out(0) = '0' then
                    decode_state_next <= IDLE;
                    decoding_done <= '1';
                    sample_next <= sample + 1;
                else
                    decode_state_next <= BIT_2;
                    audio_fifo_read_enable <= '1';
                end if;

            when BIT_2 =>
                -- 1 1 0 ~> new sample = previous sample - 1
                if audio_fifo_data_out(0) = '0' then
                    decode_state_next <= IDLE;
                    decoding_done <= '1';
                    sample_next <= sample - 1;
                else
                    decode_state_next <= NEW_SAMPLE;
                    audio_fifo_read_enable <= '1';
                end if;

            when NEW_SAMPLE =>
                -- 1 1 1 x x x x ~> new sample = next four bits
                sample_next <= sample(sample'left - 1 downto 0) & audio_fifo_data_out(0); -- TODO: Correct order?
                sample_bit_counter_next <= sample_bit_counter + 1;

                if sample_bit_counter = SAMPLE_DEPTH - 1 then
                    decode_state_next <= IDLE;
                    decoding_done <= '1';
                else
                    audio_fifo_read_enable <= '1';
                end if;
        end case;
    end process;
end architecture;
