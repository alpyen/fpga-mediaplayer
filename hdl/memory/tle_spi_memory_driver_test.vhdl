library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.ceil;

library unisim;
use unisim.vcomponents.all;

entity tle_spi_memory_driver_test is
    port (
        clk100mhz: in std_ulogic;
        reset: in std_ulogic;

        -- Controlling the Memory Driver
        start_button: in std_ulogic;
        address_switches: in std_ulogic_vector(15 downto 0);
        data_leds: out std_ulogic_vector(7 downto 0);

        start_pulse_led: out std_ulogic;

        -- SPI ports
        spi_cs_n: out std_ulogic;
        spi_sdi: inout std_ulogic;
        spi_sdo: inout std_ulogic;
        spi_wp_n: inout std_ulogic;
        spi_hold_n: inout std_ulogic
    );
end entity;

architecture tle of tle_spi_memory_driver_test is
    component clocking_wizard
        port (
            clk100mhz : in  std_ulogic;
            reset : in std_ulogic;
            clk10mhz : out std_ulogic;
            locked : out std_ulogic
        );
    end component;

    signal clk10mhz: std_ulogic;
    signal reset_debounced: std_ulogic;

    signal start_debounced: std_ulogic;
    signal start_pulse, start_is_held: std_ulogic;
    signal address: std_ulogic_vector(23 downto 0);

    -- SPI SCLK is not directly drivable on Artix7 devices
    -- it has to be accessed through the STARTUPE2 primitive.
    -- Technically we could route clk10mhz immediately to USRCCLKO
    -- instead of routing it into the spi_memory_driver and then to it
    -- but this way it's more consistent and Vivado shortens it anyway.
    signal spi_sclk: std_ulogic;
    signal wp, hold: std_ulogic;

    -- Button state has to remain for 100 ms
    constant DEBOUNCE_THRESHHOLD: positive := integer(ceil(real(10e6) * (100.0 / 1000.0)));
begin
    STARTUPE2_inst: STARTUPE2
    generic map (
        PROG_USR => "FALSE",
        SIM_CCLK_FREQ => 0.0
    )
    port map (
        CFGCLK    => open,
        CFGMCLK   => open,
        EOS       => open,
        PREQ      => open,
        CLK       => '0',
        GSR       => '0',
        GTS       => '0',
        KEYCLEARB => '1',
        PACK      => '0',
        USRCCLKO  => spi_sclk,
        USRCCLKTS => '0',
        USRDONEO  => '1',
        USRDONETS => '0'
    );

    clocking_wizard_inst: clocking_wizard
    port map (
        clk100mhz => clk100mhz,
        reset     => '0',
        clk10mhz  => clk10mhz,
        locked    => open
    );

    reset_debouncer: entity work.debouncer
    generic map (
        COUNT => DEBOUNCE_THRESHHOLD
    )
    port map (
        clk    => clk10mhz,
        input  => reset,
        output => reset_debounced
    );

    start_debouncer: entity work.debouncer
    generic map (
        COUNT => DEBOUNCE_THRESHHOLD
    )
    port map (
        clk    => clk10mhz,
        input  => start_button,
        output => start_debounced
    );

    start_pulse_led <= start_pulse;

    process (clk10mhz)
    begin
        if rising_edge(clk10mhz) then
            if reset_debounced = '1' then
                start_pulse <= '0';
                start_is_held <= '0';
            else
                start_pulse <= '0';

                if start_is_held = '0' and start_debounced = '1' then
                    start_pulse <= '1';
                    start_is_held <= '1';
                elsif start_is_held = '1' and start_debounced = '0' then
                    start_is_held <= '0';
                end if;                
            end if;
        end if;
    end process;

    spi_wp_n <= not wp;
    spi_hold_n <= not hold;

    address <= (23 downto 16 => '0') & address_switches;

    spi_memory_driver_inst: entity work.spi_memory_driver
    port map (
        clk     => clk10mhz,
        reset   => reset_debounced,
        address => address,
        data    => data_leds,
        start   => start_pulse,
        done    => open,
        sclk    => spi_sclk,
        cs_n    => spi_cs_n,
        sdi     => spi_sdi,
        sdo     => spi_sdo,
        wp      => wp,
        hold    => hold
    );
end architecture;