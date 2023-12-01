library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.log2;
use ieee.math_real.ceil;

entity i2s_master is
    generic (
        SAMPLE_DEPTH: positive;

        I2S_MCLK_SPEED: positive;
        TRANSFER_PARTNER_CLOCK_SPEED: positive
    );
    port (
        -- Audio Driver's reset ~> synchronization necessary!
        -- We have to guarantee the pulse is long enough
        -- but since we mapped reset to a button we take it as a given.
        reset: in std_ulogic;

        i2s_mclk: in std_ulogic;
        i2s_lrck: out std_ulogic;
        i2s_sdata: out std_ulogic
    );
end entity;

architecture arch of i2s_master is
    signal reset_sync, reset_sync_next: std_ulogic_vector(1 downto 0);

    -- LRCK needs to toggle at 44.1 kHz which is 1/256 of MCLK
    signal lrck_counter, lrck_counter_next: unsigned(7 downto 0) := to_unsigned(0, 8);
    signal left_right_select, left_right_select_next: std_ulogic := '0';

    -- The current sample that should be played.
    signal sample, sample_next: signed(SAMPLE_DEPTH - 1 downto 0);
    -- The next sample that should be played after sample was played.
    signal new_sample, new_sample_next: signed(sample'range);

    -- One i2s_mclk has to be stalled after an edge on lrck according to the CS4344 specification.
    signal i2s_sdata_shiftregister, i2s_sdata_shiftregister_next: std_ulogic_vector(sample'length downto 0);
begin
    i2s_lrck <= left_right_select;
    i2s_sdata <= i2s_sdata_shiftregister(i2s_sdata_shiftregister'left);

    sync: process (reset, reset_sync)
    begin
        reset_sync_next <= reset_sync(0) & reset;
    end process;

    seq: process (i2s_mclk)
    begin
        if falling_edge(i2s_mclk) then
            -- Resetting reset_sync to "00" when we encounter a reset
            -- will not reset it for one cycle as it has to be synchronized again.
            -- Therefore we simply not reset it at all.
            -- This also means that we need to clock it regardless of it being reset.
            reset_sync <= reset_sync_next;

            if reset_sync(1) = '1' then
                -- reset_sync <= (others => '0');

                lrck_counter <= to_unsigned(0, lrck_counter'length);
                left_right_select <= '0';

                sample <= to_signed(0, sample'length);
                new_sample <= to_signed(0, new_sample'length);
                i2s_sdata_shiftregister <= (others => '0');
            else
                lrck_counter <= lrck_counter_next;
                left_right_select <= left_right_select_next;

                sample <= sample_next;
                new_sample <= new_sample_next;
                i2s_sdata_shiftregister <= i2s_sdata_shiftregister_next;
            end if;
        end if;
    end process;

    comb: process (lrck_counter, left_right_select, i2s_sdata_shiftregister, new_sample)
    begin
        lrck_counter_next <= lrck_counter + 1;
        left_right_select_next <= left_right_select;

        sample_next <= sample;
        i2s_sdata_shiftregister_next <= i2s_sdata_shiftregister(i2s_sdata_shiftregister'left - 1 downto 0) & '0';

        if lrck_counter = 255 then
            left_right_select_next <= not left_right_select;

            -- One cycle stalling necessary after an edge on left right.
            i2s_sdata_shiftregister_next <= '0' & std_ulogic_vector(sample);

            -- We are on the right / last channel and about to go to the left / first
            -- and need to play a new sample if one is available.
            if left_right_select = '1' then
                sample_next <= new_sample;
                i2s_sdata_shiftregister_next <= '0' & std_ulogic_vector(new_sample);

                -- NOTE: We need to flag somehow that new_sample has been played
                --       and that the transfer fsm is now allowed to override it.
            end if;
        end if;
    end process;

    -- The i2s_master is being fed by the audio_driver component.
    -- While the first one is being run with the i2s_mclk (11.2896 MHz)
    -- the audio driver runs at a different clock (10 MHz for now)
    -- and that clock is not specified to stay at 10 MHz, it can
    -- go slower or faster.
    -- For this reason, we need a solid way to transfer data in between.
    -- Namely from the driver to the master to transmit the samples.
    -- A fifo like the audio/video fifo could do the trick, but
    -- we only need to send one sample and not burst multiple
    -- and a minimum Fifo would waste lots of ressources.
    -- So we make up our own way of crossing that clock domain.
    -- The way we will implement it is by sending one bit of data/control
    -- and holding it until it is acknowledged or timed out.
    --
    -- Necessary signals: transfer_ {ready, data, data_valid, acknowledge}
    --
    -- 0. The I2S-Master asserts 'ready' when it can receive a new sample.
    --      It does this for atleast 2x the OTHER CLOCKS duration.
    --      This happens with every signal in this transfer unless noted otherwise!
    --
    -- 1. The Audio Driver initiates a transfer by checking 'ready' = 1 and
    --    places a sample on the 'data' lines.
    --
    -- 2. Now the Audio Driver asserts the 'data_valid' line.
    --      The reason why the Audio Driver places the data first
    --      and the valid lines after a cdc-cycle is that we cannot match trace lengths
    --      and not guarantee that the other clock will read a good sample when valid is high.
    --      Therefore we give it one cdc-cycle to resolve, this way we only need to
    --      synchronize 'data_valid' on the other end, since 'data' is being held
    --      it will be clear of any metastability.
    --
    -- 3. The I2S-Master sees that the data is valid and stores the new sample
    --    and deasserts the 'ready' line.
    --
    -- 4. The I2S-Master asserts the 'data_acknowledge' line.
    --
    -- 5. The Audio Driver sees that the data has been acknowledged and deasserts 'data_valid'.
    --
    -- 6. The I2S-Master sees that the 'data_valid' line has been deasserted and deasserts 'data_acknowledge'.
    --
    -- 7. The transfer is over cleanly. We do not need to worry about jumping accidentally into a new transfer
    --    because ready has been cleared before ack was asserted.
    --
    -- The inherent clocking gives us a schedule on when to treat a transaction
    -- as timed out, incase the synchronization fails.

end architecture;
