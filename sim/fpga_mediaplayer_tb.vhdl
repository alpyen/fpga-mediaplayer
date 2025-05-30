library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fpga_mediaplayer_tb is
end entity;

architecture tb of fpga_mediaplayer_tb is
    constant T: time := 10 ns; -- 100 MHz
    signal clock, reset: std_ulogic;

    signal start: std_ulogic;

    -- SPI Interface
    signal spi_sclk: std_ulogic;
    signal spi_cs_n: std_ulogic;

    signal spi_sdi: std_logic;
    signal spi_sdo: std_logic;

    signal spi_wp_n: std_logic;
    signal spi_hold_n: std_logic;

    -- I2S interface to I2S2 PMOD
    signal i2s_mclk: std_ulogic;
    signal i2s_lrck: std_ulogic;
    signal i2s_sclk: std_ulogic;
    signal i2s_sdin: std_ulogic;

    -- Board interface to LED Board
    signal board_row_data: std_ulogic;
    signal board_shift_row_data: std_ulogic;
    signal board_apply_row_and_strobe: std_ulogic;
    signal board_row_strobe: std_ulogic;
    signal board_shift_row_strobe: std_ulogic;
    signal board_output_enable_n: std_ulogic;
begin
    process
    begin
        clock <= '1';
        wait for T/2;
        clock <= '0';
        wait for T/2;
    end process;

    process
    begin
        -- Signals have to be asserted for atleast 10*T because
        -- the fabric is clocked with 10 MHz, not 100 MHz.

        -- Wait some time for the PLL to lock itself.
        wait for 200*T;

        wait until rising_edge(clock);
        reset <= '1';
        start <= '0';
        wait for 200*T;
        wait until rising_edge(clock);

        -- The fabric clock is available on spi_sclk in the testbench.
        -- From now on we need to set the tb signals on this signal.

        wait until rising_edge(spi_sclk);
        reset <= '0';
        wait for 30*T;
        wait until rising_edge(spi_sclk);

        wait until rising_edge(spi_sclk);
        start <= '1';
        wait for 30*T;
        wait until rising_edge(spi_sclk);

        wait until rising_edge(spi_sclk);
        start <= '0';
        wait for 30*T;
        wait until rising_edge(spi_sclk);

        wait;
    end process;

    spi_flash_model_inst: entity work.spi_flash_model
    generic map (
        SIZE       => 8 * 1024,
        INIT_FILE  => "../../../../../python/media/demo_short_8x6.bin",
        INIT_VALUE => x"ff"
    )
    port map (
        sclk   => spi_sclk,
        cs_n   => spi_cs_n,
        sdi    => spi_sdi,
        sdo    => spi_sdo,
        wp_n   => spi_wp_n,
        hold_n => spi_hold_n
    );

    small_led_board_inst: entity work.small_led_board
    port map (
        row_data             => board_row_data,
        shift_row_data       => board_shift_row_data,
        apply_row_and_strobe => board_apply_row_and_strobe,
        row_strobe           => board_row_strobe,
        shift_row_strobe     => board_shift_row_strobe,
        output_enable_n      => board_output_enable_n,

        tb_row_data          => open,
        tb_row_strobe        => open
    );

    fpga_mediaplayer_inst: entity work.fpga_mediaplayer
    generic map(
        SIMULATION => true,

        WIDTH      => 8,
        HEIGHT     => 6
    )
    port map (
        clock100mhz                => clock,
        reset                      => reset,

        start_button               => start,

        -- SPI Interface
        spi_sclk                   => spi_sclk,
        spi_cs_n                   => spi_cs_n,

        spi_sdi                    => spi_sdi,
        spi_sdo                    => spi_sdo,

        spi_wp_n                   => spi_wp_n,
        spi_hold_n                 => spi_hold_n,

        -- I2S interface to I2S2 PMOD
        i2s_mclk                   => i2s_mclk,
        i2s_lrck                   => i2s_lrck,
        i2s_sclk                   => i2s_sclk,
        i2s_sdin                   => i2s_sdin,

        -- Board interface to LED Board
        board_row_data             => board_row_data,
        board_shift_row_data       => board_shift_row_data,
        board_apply_row_and_strobe => board_apply_row_and_strobe,
        board_row_strobe           => board_row_strobe,
        board_shift_row_strobe     => board_shift_row_strobe,
        board_output_enable_n      => board_output_enable_n
    );
end architecture;
