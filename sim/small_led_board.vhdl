-- Simulation model of the small LED board
-- The implementation is different from the bigger board

library ieee;
use ieee.std_logic_1164.all;

entity small_led_board is
port (
    row_data: in std_ulogic;
    shift_row_data: in std_ulogic;
    apply_row_and_strobe: in std_ulogic;

    row_strobe: in std_ulogic;
    shift_row_strobe: in std_ulogic;
    output_enable_n: in std_ulogic;

    tb_row_data: out std_ulogic_vector(7 downto 0);
    tb_row_strobe: out std_ulogic_vector(7 downto 0)
);
end entity;

architecture functional of small_led_board is
    signal row_data_int: std_ulogic_vector(7 downto 0);
    signal row_strobe_int: std_ulogic_vector(7 downto 0);
begin
    -- Route these out for the testbench to assert.
    tb_row_data <= row_data_int;
    tb_row_strobe <= row_strobe_int;

    -- Technically the board components have changed from v1
    -- but the difference in functionality is minuscule.
    -- Instead of the 595 for the row data we use a TPIC6B595N
    -- which is a open-drain power shift register so the row_data_int
    -- would be pulled to 'Z' and not '0'.
    sr_row_data: entity work.u74hc595a
    port map (
        srclk   => shift_row_data,
        rclk    => apply_row_and_strobe,
        oe_n    => output_enable_n,
        srclr_n => '1',
        ser     => row_data,
        q       => row_data_int,
        qh_buf  => open
    );

    -- Board uses 74HCT595 but functionally it is equivalent
    sr_row_strobe: entity work.u74hc595a
    port map (
        srclk   => shift_row_strobe,
        rclk    => apply_row_and_strobe,
        oe_n    => output_enable_n,
        srclr_n => '1',
        ser     => row_strobe,
        q       => row_strobe_int,
        qh_buf  => open
    );
end architecture;
