library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity small_led_board_tb is
end entity;

architecture tb of small_led_board_tb is    
    constant T: time := 10 ns;

    signal 
        row_data_in, row_data_in_n, 
        shift_row_data, shift_row_data_n, 
        apply_new_row, apply_new_row_n
    : std_ulogic;
    
    signal 
        row_strobe_in, row_strobe_in_n, 
        shift_row_strobe, shift_row_strobe_n, 
        apply_new_row_strobe, apply_new_row_strobe_n
    : std_ulogic;

    signal row_values: std_ulogic_vector(7 downto 0);
    signal row_selection_values: std_ulogic_vector(15 downto 0);
begin
    row_data_in_n <= not row_data_in;
    shift_row_data_n <= not shift_row_data;
    apply_new_row_n <= not apply_new_row;

    row_strobe_in_n <= not row_strobe_in;
    shift_row_strobe_n <= not shift_row_strobe;
    apply_new_row_strobe_n <= not apply_new_row_strobe;

    dut: entity work.small_led_board
    port map (
        row_data_in_n          => row_data_in_n,
        shift_row_data_n       => shift_row_data_n,
        apply_new_row_n        => apply_new_row_n,
        row_strobe_in_n        => row_strobe_in_n,
        shift_row_strobe_n     => shift_row_strobe_n,
        apply_new_row_strobe_n => apply_new_row_strobe_n,
        row_values             => row_values,
        row_selection_values   => row_selection_values
    );

	process
        procedure shift_row_data_in (data: in std_ulogic_vector(7 downto 0)) is
        begin
            row_data_in <= data(data'left);
            wait for T;

            for i in data'left-1 downto data'right loop
                shift_row_data <= '1';
                row_data_in <= data(i);
                wait for T/2;
                shift_row_data <= '0';
                wait for T/2;
            end loop;

            shift_row_data <= '1';
            wait for T/2;
            shift_row_data <= '0';
            wait for T/2;
        end procedure;

        procedure apply_new_row_data is
        begin
            apply_new_row <= '1';
            wait for T/2;
            apply_new_row <= '0';
            wait for T/2;
        end procedure;

        procedure shift_row_strobe_in (strobe: in integer) is
        begin
            row_strobe_in <= std_ulogic(to_unsigned(strobe, 1)(0));
            wait for T;
            shift_row_strobe <= '1';
            row_strobe_in <= '0';
            wait for T/2;
            shift_row_strobe <= '0';
            wait for T/2;
        end procedure;

        procedure apply_row_selection is
        begin
            apply_new_row_strobe <= '1';
            wait for T/2;
            apply_new_row_strobe <= '0';
            wait for T/2;
        end procedure;
    begin
        wait for 2*T;

        row_data_in <= '0';
        shift_row_data <= '0';
        apply_new_row <= '0';

        row_strobe_in <= '0';
        shift_row_strobe <= '0';
        apply_new_row_strobe <= '0';

        wait for 2*T;

        shift_row_data_in("10111101");
        assert row_values = (row_values'range => 'U');

        apply_new_row_data;
        assert row_values = "10111101";
        
        shift_row_strobe_in(0);
        assert row_selection_values = (15 downto 0 => 'U');

        apply_row_selection;
        assert row_selection_values = (15 downto 1 => 'U') & '0';
        
        shift_row_data_in("01000010");
        shift_row_strobe_in(1);

        assert row_values = "10111101";
        assert row_selection_values = (15 downto 1 => 'U') & '0';
        
        apply_new_row_data;
        apply_row_selection;

        assert row_values = "01000010";
        assert row_selection_values = (15 downto 2 => 'U') & "10";
        
        wait;
    end process;

end architecture;
