Simulador RISC-V RV32I 

En testbench.sv cambiar SELECT_CASE para elegir la prueba:
0 = los cuatro programas
1 = arithmetic.bin
2 = memory.bin
3 = branches.bin
4 = jumps.bin

STEP_LIMIT controla el maximo de instrucciones por programa.
Por ejemplo, SELECT_CASE = 1 y STEP_LIMIT = 3 permite observar
los registros x1=9, x2=4, x3=13 y PC=0000000c.

El testbench crea los cuatro archivos .bin antes de cargarlos.
La carpeta ejemplos incluye copias crudas de esos programas.
El simulador admite cargar otros binarios modificando execute_case.
