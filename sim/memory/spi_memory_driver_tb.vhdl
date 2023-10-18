library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_memory_driver_tb is
end entity;

architecture tb of spi_memory_driver_tb is
    constant T: time := 10 ns;
    signal sim_done: boolean;

    signal clk, reset: std_ulogic;

    signal address: std_ulogic_vector(23 downto 0);
    signal data: std_ulogic_vector(7 downto 0);
    signal start, done: std_ulogic;

    signal sclk, cs_n, sdi, sdo, wp, hold: std_ulogic;
    
    constant FLASH_SIZE: integer := 256;
    signal tb_memory: std_ulogic_vector(FLASH_SIZE * 8 - 1 downto 0); 
begin
    process
    begin
        clk <= '1';
        wait for T/2;
        clk <= '0';
        wait for T/2;

        if sim_done then
            wait;
        end if;
    end process;

    process
    begin
        wait for 2*T;
        reset <= '1';
        start <= '0';
        wait for 3*T;

        reset <= '0';
        wait until rising_edge(clk);

        for i in 0 to FLASH_SIZE-1 loop
            address <= std_ulogic_vector(to_unsigned(i, address'length));
            start <= '1';
            wait until rising_edge(clk);

            start <= '0';
            wait until done = '1';
            wait until rising_edge(clk);

            assert data = tb_memory(i*8+7 downto i*8)
                report "Invalid Data read at address " & integer'image(i) & ". " & 
                       "Read = " & integer'image(to_integer(unsigned(data))) & " but " & 
                       "Expected = " & integer'image(to_integer(unsigned(tb_memory(i*8+7 downto i*8))))
                severity error;
        end loop;

        report "Simulation done.";

        sim_done <= true;
        wait;
    end process;

    spi_memory_driver_dut: entity work.spi_memory_driver
    port map (
        clk     => clk,
        reset   => reset,

        -- Memory Driver Interface
        address => address,
        data    => data,
        start   => start,
        done    => done,

        -- SPI Interface
        sclk    => sclk,
        cs_n    => cs_n,
        sdi     => sdi,
        sdo     => sdo,
        wp      => wp,
        hold    => hold
    );

    spi_flash_model_inst: entity work.spi_flash_model
    generic map (
        SIZE       => FLASH_SIZE,
        INIT_FILE  => "../../../../../sim/memory/memory_file.dat",
        INIT_VALUE => x"ff"
    )
    port map (
        sclk => sclk,
        cs_n => cs_n,
        sdi  => sdi,
        sdo  => sdo,
        wp   => wp,
        hold => hold,
        
        tb_memory => tb_memory
    );
end architecture;
