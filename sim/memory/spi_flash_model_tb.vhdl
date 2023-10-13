library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_flash_model_tb is
end entity;

architecture tb of spi_flash_model_tb is
    signal sclk, cs_n, sdi, sdo, wp, hold: std_ulogic;
begin
    dut: entity work.spi_flash_model
    generic map (
        SIZE      => 8 * 1024, -- 8 KB
        INIT_FILE => "../../../../../sim/memory/memory_file.dat",
        INIT_VALUE => x"FF"
    )
    port map (
        sclk => sclk,
        cs_n => cs_n,
        sdi  => sdi,
        sdo  => sdo,
        wp   => wp,
        hold => hold
    );
end architecture;
