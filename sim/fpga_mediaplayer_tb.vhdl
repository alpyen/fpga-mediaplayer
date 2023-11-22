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

    signal spi_sdi: std_ulogic;
    signal spi_sdo: std_ulogic;

    signal spi_wp_n: std_ulogic;
    signal spi_hold_n: std_ulogic;

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
        wait for 20*T;

        reset <= '1';
        start <= '0';
        wait for 200*T;
        wait until rising_edge(clock);

        reset <= '0';
        wait for 30*T;

        start <= '1';
        wait for 30*T;
        wait until rising_edge(clock);

        start <= '0';
        wait;
    end process;

    spi_flash_model_inst: entity work.spi_flash_model
    generic map (
        SIZE       => 8 * 1024,
        INIT_FILE  => "../../../../../python/loop_short.enc",
        INIT_VALUE => x"ff"
    )
    port map (
        sclk      => spi_sclk,
        cs_n      => spi_cs_n,
        sdi       => spi_sdi,
        sdo       => spi_sdo,
        wp_n      => spi_wp_n,
        hold_n    => spi_hold_n
    );

    fpga_mediaplayer_inst: entity work.fpga_mediaplayer
    generic map(
        SIMULATION => true
    )
    port map (
        clock100mhz  => clock,
        reset        => reset,

        -- SPI Interface
        spi_sclk     => spi_sclk,
        spi_cs_n     => spi_cs_n,

        spi_sdi      => spi_sdi,
        spi_sdo      => spi_sdo,

        spi_wp_n     => spi_wp_n,
        spi_hold_n   => spi_hold_n,

        start_button => start
    );
end architecture;
