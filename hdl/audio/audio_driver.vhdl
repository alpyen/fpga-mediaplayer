library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
    type state_t is (IDLE, REQUEST, BIT_ONE, BIT_TWO, BIT_THREE, NEW_SAMPLE, DONE);
    signal state, state_next: state_t;

    signal sample, sample_next: signed(3 downto 0);
begin
    seq: process (clock)
    begin
        if reset = '1' then
            state <= IDLE;

            sample <= (others => '0');
        elsif rising_edge(clock) then
            state <= state_next;

            sample <= sample_next;
        end if;
    end process;

    fsm: process (
        state,
        audio_driver_start, audio_fifo_data_out, audio_fifo_empty,
        sample
    )
    begin
        state_next <= state;

        audio_fifo_read_enable <= '0';

        sample_next <= sample;

        case state is
            when IDLE =>
                if audio_driver_start = '1' then
                    state_next <= REQUEST;
                end if;

            when REQUEST =>
                if audio_fifo_empty = '0' then
                    state_next <= BIT_ONE;
                    audio_fifo_read_enable <= '1';
                end if;

            when BIT_ONE =>
                -- 0 ~> Sample unchanged to previous one
                if audio_fifo_data_out = '0' then
                    state_next <= DONE;
                    -- sample_next <= sample;
                else
                    -- The Fifo keeps the word on the data output if no new read is dispatched
                    -- this means we don't need to store a flag that we are waiting for the fifo output.
                    if audio_fifo_empty /= '0' then
                        state_next <= BIT_TWO;
                        audio_fifo_read_enable <= '1';
                    end if;
                end if;

            when BIT_TWO =>
                -- 1 0 ~> Sample +1 compared to the previous one
                if audio_fifo_data_out = '0' then
                    state_next <= DONE;
                    sample_next <= sample + 1;
                else
                    if audio_fifo_empty /= '0' then
                        state_next <= BIT_THREE;
                        audio_fifo_read_enable <= '1';
                    end if;
                end if;

            when BIT_THREE =>
                -- 1 1 0 ~> Sample -1 compared to the previous one
                if audio_fifo_data_out = '0' then
                    state_next <= DONE;
                    sample_next <= sample - 1;
                else
                    if audio_fifo_empty /= '0' then
                        state_next <= NEW_SAMPLE;
                        audio_fifo_read_enable <= '1';
                    end if;
                end if;

            when NEW_SAMPLE =>
                null;
        end case;
    end process;
end architecture;
