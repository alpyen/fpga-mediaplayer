library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.log2;
use ieee.math_real.ceil;

entity audio_driver is
    generic (
        CLOCK_SPEED: positive;
        I2S_MCLK_SPEED: positive
    );
    port (
        clock: in std_ulogic;
        reset: in std_ulogic;

        -- Audio Driver Interface
        audio_driver_play: in std_ulogic;
        audio_driver_done: out std_ulogic;

        -- Audio Fifo
        audio_fifo_read_enable: out std_ulogic;
        audio_fifo_data_out: in std_ulogic_vector(0 downto 0);
        audio_fifo_empty: in std_ulogic;

        -- I2S Interface
        i2s_mclk: in std_ulogic;
        i2s_lrck: out std_ulogic;
        i2s_sclk: out std_ulogic;
        i2s_sdin: out std_ulogic
    );
end entity;

architecture arch of audio_driver is
    -- This constant is here to not use magic numbers.
    -- The audio driver is "optimized" to work on four bit samples.
    -- The encoding of 0/+1/-1 doesn't make much sense with higher bit depths
    -- since the jumps are mostly wider than 0/+1/-1.
    constant SAMPLE_DEPTH: positive := 4;

    -- Audio Driver FSM
    type state_t is (IDLE, DECODE, WAIT_UNTIL_SAMPLE_PLAYED);
    signal state, state_next: state_t;
    signal decoding_start, sending_start: std_ulogic;

    -- Decoder FSM
    type decode_state_t is (IDLE, BIT_0, BIT_1, BIT_2, NEW_SAMPLE);
    signal decode_state, decode_state_next: decode_state_t;
    signal decoding_done: std_ulogic;

    signal sample, sample_next: signed(SAMPLE_DEPTH - 1 downto 0);
    signal sample_bit_counter, sample_bit_counter_next: unsigned(integer(ceil(log2(real(SAMPLE_DEPTH)))) - 1 downto 0);

    -- I2S Transfer FSM
    signal transfer_ready: std_ulogic;
    signal transfer_ready_sync, transfer_ready_sync_next: std_ulogic_vector(1 downto 0);
    signal transfer_data, transfer_data_next: signed(sample'range);
    signal transfer_data_valid, transfer_data_valid_next: std_ulogic;
    signal transfer_acknowledge: std_ulogic;
    signal transfer_acknowledge_sync, transfer_acknowledge_sync_next: std_ulogic_vector(1 downto 0);

    constant CDC_HOLD_COUNT_NUM: positive := positive(2 * ((CLOCK_SPEED + I2S_MCLK_SPEED - 1) / I2S_MCLK_SPEED));
    constant CDC_HOLD_COUNT_WIDTH: integer := integer(ceil(log2(real(CDC_HOLD_COUNT_NUM))));
    constant CDC_HOLD_COUNT: unsigned(CDC_HOLD_COUNT_WIDTH - 1 downto 0) := to_unsigned(CDC_HOLD_COUNT_NUM - 1, CDC_HOLD_COUNT_WIDTH);
    signal cdc_counter, cdc_counter_next: unsigned(CDC_HOLD_COUNT'range);

    type transfer_state_t is (
        IDLE,
        WAIT_UNTIL_READY_ASSERTED,
        WAIT_UNTIL_DATA_ASSERTED,
        WAIT_UNTIL_DATA_VALID_ASSERTED,
        WAIT_UNTIL_ACKNOWLEDGE_ASSERTED,
        WAIT_UNTIL_DATA_VALID_DEASSERTED
    );
    signal transfer_state, transfer_state_next: transfer_state_t;
    signal sending_done: std_ulogic;
begin
    i2s_master_inst: entity work.i2s_master
    generic map (
        SAMPLE_DEPTH => SAMPLE_DEPTH,

        I2S_MCLK_SPEED => I2S_MCLK_SPEED,
        TRANSFER_PARTNER_CLOCK_SPEED => CLOCK_SPEED
    )
    port map (
        reset                => reset,

        i2s_mclk             => i2s_mclk,
        i2s_lrck             => i2s_lrck,
        i2s_sclk             => i2s_sclk,
        i2s_sdin             => i2s_sdin,

        transfer_ready       => transfer_ready,
        transfer_data        => transfer_data,
        transfer_data_valid  => transfer_data_valid,
        transfer_acknowledge => transfer_acknowledge
    );

    sync: process (transfer_ready, transfer_ready_sync, transfer_acknowledge, transfer_acknowledge_sync)
    begin
        transfer_ready_sync_next <= transfer_ready_sync(0) & transfer_ready;
        transfer_acknowledge_sync_next <= transfer_acknowledge_sync(0) & transfer_acknowledge;
    end process;

    seq: process (clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                state <= IDLE;

                decode_state <= IDLE;
                sample <= to_signed(0, sample'length);
                sample_bit_counter <= to_unsigned(0, sample_bit_counter'length);

                transfer_state <= IDLE;
                transfer_ready_sync <= (others => '0');
                transfer_acknowledge_sync <= (others => '0');
                transfer_data <= to_signed(0, transfer_data'length);
                transfer_data_valid <= '0';
                cdc_counter <= to_unsigned(0, cdc_counter'length);
            else
                state <= state_next;

                decode_state <= decode_state_next;
                sample <= sample_next;
                sample_bit_counter <= sample_bit_counter_next;

                transfer_state <= transfer_state_next;
                transfer_ready_sync <= transfer_ready_sync_next;
                transfer_acknowledge_sync <= transfer_acknowledge_sync_next;
                transfer_data <= transfer_data_next;
                transfer_data_valid <= transfer_data_valid_next;
                cdc_counter <= cdc_counter_next;
            end if;
        end if;
    end process;

    fsm: process (state, audio_driver_play, audio_fifo_empty, decoding_done, sending_done)
    begin
        state_next <= state;

        decoding_start <= '0';
        sending_start <= '0';

        audio_driver_done <= '0';

        case state is
            when IDLE =>
                audio_driver_done <= '1';

                if audio_driver_play = '1' and audio_fifo_empty /= '1' then
                    state_next <= DECODE;
                end if;

            when DECODE =>
                if decoding_done = '1' then
                    state_next <= WAIT_UNTIL_SAMPLE_PLAYED;
                else
                    if audio_fifo_empty /= '1' then
                        decoding_start <= '1';
                    else
                        -- Only jump back to idle when audio_driver_play is not asserted anymore.
                        -- This notifies us that there will be no data inserted anymore into the Fifo.
                        if audio_driver_play = '0' then
                            state_next <= IDLE;
                        end if;
                    end if;
                end if;

            when WAIT_UNTIL_SAMPLE_PLAYED =>
                if sending_done = '1' then
                    state_next <= DECODE;
                else
                    sending_start <= '1';
                end if;
        end case;
    end process;

    transfer_fsm: process (
        transfer_state, sending_start, transfer_ready_sync, cdc_counter, sample,
        transfer_acknowledge_sync, transfer_data, transfer_data_valid
    )
    begin
        transfer_state_next <= transfer_state;
        sending_done <= '0';
        cdc_counter_next <= to_unsigned(0, cdc_counter'length);

        transfer_data_next <= transfer_data;
        transfer_data_valid_next <= transfer_data_valid;

        case transfer_state is
            when IDLE =>
                -- We could probably get rid of this state.
                transfer_state_next <= WAIT_UNTIL_READY_ASSERTED;

            when WAIT_UNTIL_READY_ASSERTED =>
                if transfer_ready_sync(1) = '1' and sending_start = '1' then
                    transfer_state_next <= WAIT_UNTIL_DATA_ASSERTED;
                    transfer_data_next <= sample;
                end if;

            when WAIT_UNTIL_DATA_ASSERTED =>
                cdc_counter_next <= cdc_counter + 1;

                if cdc_counter = CDC_HOLD_COUNT then
                    transfer_state_next <= WAIT_UNTIL_DATA_VALID_ASSERTED;
                    transfer_data_valid_next <= '1';
                end if;

            when WAIT_UNTIL_DATA_VALID_ASSERTED =>
                cdc_counter_next <= cdc_counter + 1;

                if cdc_counter = CDC_HOLD_COUNT then
                    transfer_state_next <= WAIT_UNTIL_ACKNOWLEDGE_ASSERTED;
                end if;

            when WAIT_UNTIL_ACKNOWLEDGE_ASSERTED =>
                if transfer_acknowledge_sync(1) = '1' then
                    transfer_state_next <= WAIT_UNTIL_DATA_VALID_DEASSERTED;
                    transfer_data_valid_next <= '0';
                end if;

            when WAIT_UNTIL_DATA_VALID_DEASSERTED =>
                cdc_counter_next <= cdc_counter + 1;

                if cdc_counter = CDC_HOLD_COUNT then
                    transfer_state_next <= IDLE;
                    sending_done <= '1';
                end if;
        end case;
    end process;

    decode_fsm: process (decode_state, decoding_start, audio_fifo_data_out, sample, sample_bit_counter)
    begin
        decode_state_next <= decode_state;
        decoding_done <= '0';

        sample_next <= sample;
        sample_bit_counter_next <= to_unsigned(0, sample_bit_counter'length);

        audio_fifo_read_enable <= '0';

        case decode_state is
            when IDLE =>
                if decoding_start = '1' then
                    decode_state_next <= BIT_0;
                    audio_fifo_read_enable <= '1';

                    -- We assume that a full encoded sample is available in the Fifo.
                    -- If there is no sample we stay in IDLE because decoding_start wasn't asserted.
                    -- But once it is asserted, then one sample is atleast in there (min. 1 bits, max. 7 bits).
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
                sample_next <= sample(sample'left - 1 downto 0) & audio_fifo_data_out(0);
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
