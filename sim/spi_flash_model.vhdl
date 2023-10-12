-- Functional model of the onboard SPI flash (Macronix / Spansion)
-- This model only supports the basic READ command

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.sim_pkg.all;

entity spi_flash_model is
generic (
    SIZE: integer := 2 ** 24; -- in MB
    INIT_FILE: string
);
port (
    sclk: in std_ulogic;
    cs_n: in std_ulogic;

    sdi: in std_ulogic;
    sdo: out std_ulogic;

    wp: in std_ulogic;
    hold: in std_ulogic
);
end entity;

architecture functional of spi_flash_model is
    type memory_t is array (0 to SIZE-1) of std_ulogic_vector(7 downto 0);
    signal memory: memory_t := (others => (others => x"FF"));
begin

end architecture;
