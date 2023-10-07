library ieee;
use ieee.std_logic_1164.all;

entity small_led_board is
port (
    row_data_in_n: in std_ulogic;
    shift_row_data_n: in std_ulogic;
    apply_new_row_n: in std_ulogic;

    row_strobe_in_n: in std_ulogic;
    shift_row_strobe_n: in std_ulogic;
    apply_new_row_strobe_n: in std_ulogic;

    row_values: out std_ulogic_vector(7 downto 0);
    row_selection_values: out std_ulogic_vector(15 downto 0)
);
end entity;

architecture functional of small_led_board is
    signal row_data_in, shift_row_data, apply_new_row: std_ulogic;
    signal row_data: std_ulogic_vector(7 downto 0);

    signal row_strobe_in, shift_row_strobe, apply_new_row_strobe: std_ulogic;
    signal row_selection_data: std_ulogic_vector(15 downto 0);
begin
    -- Route these out for the testbench to assert.
    row_values <= row_data;
    row_selection_values <= row_selection_data;

    -- The board actually uses pullups and the negated signals
    -- come from the logic shifters which can only pull the line down.
    -- For ease of simulation we'll simply assume it can drive both.
    row_data_in <= not row_data_in_n;
    shift_row_data <= not shift_row_data_n;
    apply_new_row <= apply_new_row_n;

    row_strobe_in <= not row_strobe_in_n;
    shift_row_strobe <= not shift_row_strobe_n;
    apply_new_row_strobe <= not apply_new_row_strobe_n;

    sr_row_data: entity work.u74hc595a
    port map (
        srclk   => shift_row_data,
        rclk    => apply_new_row,
        oe_n    => '0',
        srclr_n => '1',
        ser     => row_data_in,
        q       => row_data,
        qh_buf  => open
    );

    sr_row_selection_0: entity work.u74hc595a
    port map (
        srclk   => shift_row_strobe,
        rclk    => apply_new_row_strobe,
        oe_n    => '0',
        srclr_n => '1',
        ser     => row_strobe_in,
        q       => row_selection_data(7 downto 0),
        qh_buf  => open
    );

    sr_row_selection_1: entity work.u74hc595a
    port map (
        srclk   => shift_row_strobe,
        rclk    => apply_new_row_strobe,
        oe_n    => '0',
        srclr_n => '1',
        ser     => row_selection_data(2),
        q       => row_selection_data(15 downto 8),
        qh_buf  => open
    );
end architecture;
