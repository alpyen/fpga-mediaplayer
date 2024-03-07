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
        i2s_sclk: out std_ulogic;
        i2s_sdin: out std_ulogic;

        transfer_ready: out std_ulogic;
        transfer_data: in signed(SAMPLE_DEPTH - 1 downto 0);
        transfer_data_valid: in std_ulogic;
        transfer_acknowledge: out std_ulogic
    );
end entity;

architecture arch of i2s_master is
    signal reset_sync, reset_sync_next: std_ulogic_vector(1 downto 0);

    -- LRCK is equivalent to the sample rate of 44.1 kHz which is 1/256 of the MCLK.
    -- Since the line will be toggled it has to happen at twice the frequency or it gets halved.
    constant LRCK_TO_MCLK_CLOCKS_COUNT: positive := 128;
    signal lrck_counter, lrck_counter_next: unsigned(integer(ceil(log2(real(LRCK_TO_MCLK_CLOCKS_COUNT)))) - 1 downto 0);
    signal left_right_select, left_right_select_next: std_ulogic;

    -- Unlike the LRCK the data is being held for this amount of clock cycles, so no halving.
    constant MCLK_TO_SCLK_COUNT: positive := 8;
    signal sclk_counter, sclk_counter_next: unsigned(integer(ceil(log2(real(MCLK_TO_SCLK_COUNT)))) - 1 downto 0);

    -- The current sample that should be played.
    signal sample, sample_next: signed(SAMPLE_DEPTH - 1 downto 0);

    -- One i2s_mclk has to be stalled after an edge on lrck according to the CS4344 specification.
    signal i2s_sdin_shiftregister, i2s_sdin_shiftregister_next: std_ulogic_vector(sample'length downto 0);

    -- One word Fifo holds the new sample that arrived from the Audio Driver
    signal
        new_sample_fifo_read_enable, new_sample_fifo_write_enable,
        new_sample_fifo_dout_valid, new_sample_fifo_dout_valid_next,
        new_sample_fifo_full, new_sample_fifo_full_next
    : std_ulogic;
    signal
        new_sample_fifo_din, new_sample_fifo_dout, new_sample_fifo_dout_next
    : signed(sample'range);

    signal new_sample_fifo_data, new_sample_fifo_data_next: signed(sample'range);

    -- Transfer Signals
    signal transfer_ready_int, transfer_ready_int_next: std_ulogic;
    signal transfer_acknowledge_int, transfer_acknowledge_int_next: std_ulogic;
    signal transfer_data_valid_sync, transfer_data_valid_sync_next: std_ulogic_vector(1 downto 0);

    -- Technically we only need to cound to CDC_HOLD_COUNT_WIDTH - 1 so we are wasting potentially one bit on the width calculation.
    -- But that messes with the bit width if we only need to count to 2 (-1) since log2(1) = 0.
    constant CDC_HOLD_COUNT_NUM: positive := positive(2 * ((I2S_MCLK_SPEED + TRANSFER_PARTNER_CLOCK_SPEED - 1) / TRANSFER_PARTNER_CLOCK_SPEED));
    constant CDC_HOLD_COUNT_WIDTH: integer := integer(ceil(log2(real(CDC_HOLD_COUNT_NUM))));
    constant CDC_HOLD_COUNT: unsigned(CDC_HOLD_COUNT_WIDTH - 1 downto 0) := to_unsigned(CDC_HOLD_COUNT_NUM - 1, CDC_HOLD_COUNT_WIDTH);
    signal cdc_counter, cdc_counter_next: unsigned(CDC_HOLD_COUNT'range);

    type transfer_state_t is (
        IDLE,
        WAIT_UNTIL_READY_ASSERTED,
        WAIT_UNTIL_DATA_VALID_ASSERTED,
        WAIT_UNTIL_READY_DEASSERTED,
        WAIT_UNTIL_ACKNOWLEDGE_ASSERTED,
        WAIT_UNTIL_DATA_VALID_DEASSERTED,
        WAIT_UNTIL_ACKNOWLEDGE_DEASSERTED
    );
    signal transfer_state, transfer_state_next: transfer_state_t;
begin
    i2s_lrck <= left_right_select;
    i2s_sclk <= '0'; -- We are using the Internal SCLK mode
    i2s_sdin <= i2s_sdin_shiftregister(i2s_sdin_shiftregister'left);

    transfer_ready <= transfer_ready_int;
    transfer_acknowledge <= transfer_acknowledge_int;

    sync: process (reset, reset_sync, transfer_data_valid, transfer_data_valid_sync)
    begin
        reset_sync_next <= reset_sync(0) & reset;
        transfer_data_valid_sync_next <= transfer_data_valid_sync(0) & transfer_data_valid;
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

    	        sclk_counter <= to_unsigned(0, sclk_counter'length);
                lrck_counter <= to_unsigned(0, lrck_counter'length);
                left_right_select <= '0';

                sample <= to_signed(0, sample'length);
                i2s_sdin_shiftregister <= (others => '0');

                transfer_state <= IDLE;
                transfer_ready_int <= '0';
                transfer_data_valid_sync <= (others => '0');
                transfer_acknowledge_int <= '0';
                cdc_counter <= to_unsigned(0, cdc_counter'length);
            else
                sclk_counter <= sclk_counter_next;
                lrck_counter <= lrck_counter_next;
                left_right_select <= left_right_select_next;

                sample <= sample_next;
                i2s_sdin_shiftregister <= i2s_sdin_shiftregister_next;

                transfer_state <= transfer_state_next;
                transfer_ready_int <= transfer_ready_int_next;
                transfer_data_valid_sync <= transfer_data_valid_sync_next;
                transfer_acknowledge_int <= transfer_acknowledge_int_next;
                cdc_counter <= cdc_counter_next;
            end if;
        end if;
    end process;

    comb: process (
        sclk_counter, lrck_counter, left_right_select, sample,
        i2s_sdin_shiftregister,
        new_sample_fifo_full, new_sample_fifo_dout, new_sample_fifo_dout_valid
    )
    begin
        sclk_counter_next <= sclk_counter + 1;
        lrck_counter_next <= lrck_counter + 1;
        left_right_select_next <= left_right_select;

        sample_next <= sample;
        i2s_sdin_shiftregister_next <= i2s_sdin_shiftregister;

        if sclk_counter = MCLK_TO_SCLK_COUNT - 1 then
            sclk_counter_next <= to_unsigned(0, sclk_counter'length);
            i2s_sdin_shiftregister_next <= i2s_sdin_shiftregister(i2s_sdin_shiftregister'left - 1 downto 0) & '0';
        end if;

        new_sample_fifo_read_enable <= '0';

        if lrck_counter = LRCK_TO_MCLK_CLOCKS_COUNT - 1 then
            left_right_select_next <= not left_right_select;

            -- One cycle stalling necessary after an edge on left right.
            i2s_sdin_shiftregister_next <= '0' & std_ulogic_vector(sample);

            -- We are on the right / last channel and about to go to the left / first
            -- and need to play a new sample if one is available.
            if left_right_select = '1' then
                -- If there is no sample to play in the Fifo it will output a zero sample.
                if new_sample_fifo_dout_valid = '0' then
                    sample_next <= to_signed(0, sample'length);
                    i2s_sdin_shiftregister_next <= '0' & std_ulogic_vector(to_signed(0, sample'length));
                else
                    sample_next <= new_sample_fifo_dout;
                    i2s_sdin_shiftregister_next <= '0' & std_ulogic_vector(new_sample_fifo_dout);
                end if;
            end if;

        -- Dispatch Read one cycle before we need it.
        elsif lrck_counter = LRCK_TO_MCLK_CLOCKS_COUNT - 2 and left_right_select = '1' and new_sample_fifo_full = '1' then
            new_sample_fifo_read_enable <= '1';
        end if;
    end process;

    -- One word Fifo to exchange data between the Transfer and Decode FSM.
    new_sample_fifo_seq: process (i2s_mclk)
    begin
        if falling_edge(i2s_mclk) then
            if reset_sync(1) = '1' then
                new_sample_fifo_dout <= (others => '0');
                new_sample_fifo_full <= '0';
                new_sample_fifo_data <= to_signed(0, new_sample_fifo_data'length);
                new_sample_fifo_dout_valid <= '0';
            else
                new_sample_fifo_dout <= new_sample_fifo_dout_next;
                new_sample_fifo_full <= new_sample_fifo_full_next;
                new_sample_fifo_data <= new_sample_fifo_data_next;
                new_sample_fifo_dout_valid <= new_sample_fifo_dout_valid_next;
            end if;
        end if;
    end process;

    new_sample_fifo_comb: process (
        new_sample_fifo_read_enable, new_sample_fifo_write_enable,
        new_sample_fifo_din, new_sample_fifo_full, new_sample_fifo_data
    )
    begin
        new_sample_fifo_full_next <= new_sample_fifo_full;
        new_sample_fifo_data_next <= new_sample_fifo_data;
        new_sample_fifo_dout_next <= (others => '0');
        new_sample_fifo_dout_valid_next <= '0';

        -- Reading from an empty Fifo will output a zero sample.
        -- Writing to a full Fifo will overwrite its contents.
        if new_sample_fifo_read_enable = '1' and new_sample_fifo_write_enable = '1' then
            new_sample_fifo_data_next <= new_sample_fifo_din;
            new_sample_fifo_dout_next <= new_sample_fifo_data;
            new_sample_fifo_dout_valid_next <= '1';
        elsif new_sample_fifo_read_enable = '1' then
            new_sample_fifo_full_next <= '0';
            new_sample_fifo_data_next <= to_signed(0, new_sample_fifo_data'length);
            new_sample_fifo_dout_next <= new_sample_fifo_data;
            new_sample_fifo_dout_valid_next <= '1';
        elsif new_sample_fifo_write_enable = '1' then
            new_sample_fifo_full_next <= '1';
            new_sample_fifo_data_next <= new_sample_fifo_din;
        end if;
    end process;

    transfer_fsm: process (
        transfer_state, new_sample_fifo_full, transfer_ready_int,
        cdc_counter, transfer_data_valid_sync, transfer_data, transfer_acknowledge_int
    )
    begin
        transfer_state_next <= transfer_state;
        cdc_counter_next <= to_unsigned(0, cdc_counter'length);

        transfer_ready_int_next <= transfer_ready_int;
        new_sample_fifo_write_enable <= '0';
        new_sample_fifo_din <= to_signed(0, new_sample_fifo_din'length);
        transfer_acknowledge_int_next <= transfer_acknowledge_int;

        case transfer_state is
            when IDLE =>
                if new_sample_fifo_full = '0' then
                    transfer_state_next <= WAIT_UNTIL_READY_ASSERTED;
                    transfer_ready_int_next <= '1';
                end if;

            when WAIT_UNTIL_READY_ASSERTED =>
                cdc_counter_next <= cdc_counter + 1;

                if cdc_counter = CDC_HOLD_COUNT then
                    transfer_state_next <= WAIT_UNTIL_DATA_VALID_ASSERTED;
                end if;

            when WAIT_UNTIL_DATA_VALID_ASSERTED =>
                if transfer_data_valid_sync(1) = '1' then
                    transfer_state_next <= WAIT_UNTIL_READY_DEASSERTED;
                    new_sample_fifo_write_enable <= '1';
                    new_sample_fifo_din <= transfer_data;
                    transfer_ready_int_next <= '0';
                end if;

            when WAIT_UNTIL_READY_DEASSERTED =>
                cdc_counter_next <= cdc_counter + 1;

                if cdc_counter = CDC_HOLD_COUNT then
                    transfer_state_next <= WAIT_UNTIL_ACKNOWLEDGE_ASSERTED;
                    transfer_acknowledge_int_next <= '1';
                end if;

            when WAIT_UNTIL_ACKNOWLEDGE_ASSERTED =>
                cdc_counter_next <= cdc_counter + 1;

                if cdc_counter = CDC_HOLD_COUNT then
                    transfer_state_next <= WAIT_UNTIL_DATA_VALID_DEASSERTED;
                end if;

            when WAIT_UNTIL_DATA_VALID_DEASSERTED =>
                if transfer_data_valid_sync(1) = '0' then
                    transfer_state_next <= WAIT_UNTIL_ACKNOWLEDGE_DEASSERTED;
                    transfer_acknowledge_int_next <= '0';
                end if;

            when WAIT_UNTIL_ACKNOWLEDGE_DEASSERTED =>
                cdc_counter_next <= cdc_counter + 1;

                if cdc_counter = CDC_HOLD_COUNT then
                    transfer_state_next <= IDLE;
                end if;
        end case;
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
    -- 4. The I2S-Master asserts the 'acknowledge' line.
    --
    -- 5. The Audio Driver sees that the data has been acknowledged and deasserts 'data_valid'.
    --
    -- 6. The I2S-Master sees that the 'data_valid' line has been deasserted and deasserts 'acknowledge'.
    --
    -- 7. The transfer is over cleanly. We do not need to worry about jumping accidentally into a new transfer
    --    because ready has been cleared before ack was asserted.
    --
    -- The inherent clocking gives us a schedule on when to treat a transaction
    -- as timed out, incase the synchronization fails.
    --
    -- The amount to hold the CDC-signals is dependant on both clock frequencies (this and the partner).
    -- Since we want to (de)assert these signals for at least 2x the other clock, we have to satisfy this equation.
    --     x * Tsrc >= 2 * Tdst     (x being the required source-clock cycles)
    -- <=> x / Fsrc >= 2 / Fdst
    -- <=> x >= ceil(2 * (Fsrc / Fdst))
    -- since there is no real division in VHDL'93 we use the int ceiling trick: x = integer(2 * ((Fsrc + Fdst - 1) / Fdst))

end architecture;
