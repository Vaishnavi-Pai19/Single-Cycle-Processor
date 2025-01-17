//R-Type Instruction: jr $s
//we'll be calculating the new pc from the given register

//convention followed, this is not rigid:
	//one extra control signal for jr to signal when the jr instruction is made

	
//top module: no change
module SingleCycleV1(input clk, reset,output [31:0] writedata, dataadr,output memwrite);
	wire[31:0] pc,instr, readdata;
	// instantiate processor and memories
	mips mips (clk, reset, pc, instr, memwrite, dataadr,writedata, readdata);
	imem imem (pc[7:2], instr);
	dmem dmem (clk, memwrite, dataadr, writedata,readdata);
endmodule

//dmem: no change
module dmem (input clk, we,input [31:0] a, wd,output [31:0] rd);
	reg [31:0] RAM[63:0];
	assign rd = RAM[a[31:2]]; // word aligned
	always @ (posedge clk)
	if (we)
	RAM[a[31:2]] <= wd;
endmodule


//imem: change file path appropriately
module imem (input [5:0] a,output [31:0] rd);
	reg [31:0] RAM[63:0];
	integer i;
	initial
		begin
			$readmemh ("D:/SingleCycleV1/memfile.dat",RAM);
		end
	assign rd = RAM[a]; // word aligned
endmodule

//mips: control signal for jr added between modules
module  mips(input clk, reset,
				output [31:0] pc,
				input [31:0] instr,	
				output memwrite,
				output [31:0] aluout, writedata,
				input [31:0] readdata);
	
	wire memtoreg, branch,
	alusrc, regdst, regwrite, jump, jr;//jr
	wire [2:0] alucontrol;
	controller c(instr[31:26], instr[5:0], zero,memtoreg, memwrite, pcsrc,alusrc, regdst, regwrite, jump,jr, alucontrol);//jr
	datapath dp(clk, reset, memtoreg, pcsrc,alusrc, regdst, regwrite, jump,jr,alucontrol,zero, pc, instr,aluout, writedata, readdata);//jr

endmodule

//controller: jr,funct
module controller (input [5:0] op, funct,
						input zero,
						output memtoreg, memwrite,
						output pcsrc, alusrc,
						output regdst, regwrite,
						output jump,
						output jr,//jr
						output [2:0] alucontrol);
						
	wire [1:0] aluop;
	wire branch;
	maindec md (op,funct, memtoreg, memwrite, branch,alusrc, regdst, regwrite, jump,jr,aluop);
	aludec ad (op,funct, aluop, alucontrol);
	assign pcsrc = branch & zero;
endmodule

//maindec: jr, funct, case
module maindec(input [5:0] op,funct,//jr
				output memtoreg, memwrite,
				output branch, alusrc,
				output regdst, regwrite,
				output jump,
				output jr,//jr
				output [1:0] aluop);
				
	reg [9:0] controls;
	assign {regwrite, regdst, alusrc,branch, memwrite,memtoreg, jump, jr,aluop} = controls;
	always @ (*)
		case(op)
			6'b000000: 	case(funct)
								6'b001000: 	controls <=10'b0000000100; //JR
								default:		controls <=10'b1100000010; //Other Rtype
							endcase
			6'b100011: 	controls <=10'b1010010000; //LW
			6'b101011: 	controls <=10'b0010100000; //SW
			6'b000100: 	controls <=10'b0001000001; //BEQ
			6'b001000: 	controls <=10'b1010000000; //ADDI
			6'b001100: 	controls <=10'b1010000000; //ANDI
			6'b001101: 	controls <=10'b1010000000; //ORI
			6'b001110: 	controls <=10'b1010000000; //XORI
			6'b000010: 	controls <=10'b0000001000; //J
			default: 	controls  <=10'bxxxxxxxxx; //???
		endcase
endmodule

	
//aludec: no change
module aludec (input [5:0] op, input [5:0] funct,
					input [1:0] aluop,
					output reg [2:0] alucontrol);
					
	always @ (*)
		case (op) 
		6'b001100:	alucontrol <= 3'b000; // ANDI
		6'b001101:	alucontrol <= 3'b001; // ORI
		6'b001110:	alucontrol <= 3'b011; // XORI
		default: case (aluop)
			2'b00: alucontrol <= 3'b010; // add
			2'b01: alucontrol <= 3'b110; // sub
			default: case(funct) // RTYPE
				6'b100000: alucontrol <= 3'b010; // ADD
				6'b100010: alucontrol <= 3'b110; // SUB
				6'b100100: alucontrol <= 3'b000; // AND
				6'b100101: alucontrol <= 3'b001; // OR
				6'b101010: alucontrol <= 3'b111; // SLT
				default: alucontrol <= 3'bxxx; // ???
			endcase
		endcase
	endcase
endmodule





//datapath: change
module datapath (input clk, reset,
						input memtoreg, pcsrc,
						input alusrc, regdst,
						input regwrite, jump,
						input jr,
						input [2:0] alucontrol,
						output zero,
						output [31:0] pc,
						input [31:0] instr,
						output [31:0] aluout, writedata,
						input [31:0] readdata);
							
	wire [4:0] writereg;
	wire [31:0] pcnext, pcnextbr, pcplus4, pcbranch, pcnextj;
	wire [31:0] signimm, signimmsh;
	wire [31:0] srca, srcb;
	wire [31:0] result;
	
	// next PC 
	flopr #(32) pcreg(clk, reset, pcnext, pc);
	adder pcadd1 (pc, 32'b100, pcplus4);
	sl2 immsh(signimm, signimmsh);
	adder pcadd2(pcplus4, signimmsh, pcbranch);
	mux2 #(32) pcbrmux(pcplus4, pcbranch, pcsrc,pcnextbr);
	mux2 #(32) pcmux(pcnextbr, {pcplus4[31:28],instr[25:0], 2'b00},jump, pcnextj);
	mux2 #(32) pcmuxjr(pcnextj, srca, jr, pcnext); // jr
	
	// register file 
	regfile rf(clk, regwrite, instr[25:21],instr[20:16], writereg,result, srca, writedata);
	mux2 #(5) wrmux(instr[20:16], instr[15:11],regdst, writereg);
	mux2 #(32) resmux(aluout, readdata,memtoreg, result);
	signext se(instr[15:0], signimm);
	
	// ALU 
	mux2 #(32) srcbmux(writedata, signimm, alusrc,srcb);
	alu alu1(srca, srcb, alucontrol,aluout, zero);
endmodule



//regfile: no changes
module regfile (input clk,
					input we3,
					input [4:0] ra1, ra2, wa3,
					input [31:0] wd3,
					output [31:0] rd1, rd2);
	reg [31:0] rf[31:0];
	// three ported register file
	// read two ports combinationally
	// write third port on rising edge of clock
	// register 0 hardwired to 0
	always @ (posedge clk)
	if (we3) rf[wa3] <= wd3;
		assign rd1 = (ra1 != 0) ? (rf[ra1]) : 0;
		assign rd2 = (ra2 != 0) ? (rf[ra2]): 0;

endmodule



//supplementary modules: no changes
module adder (input [31:0] a, b,output [31:0] y);
		assign y=a + b;
endmodule

module sl2 (input [31:0] a,
	output [31:0] y);
	// shift left by 2
	assign y = {a[29:01], 2'b00};
endmodule


module signext (input [15:0] a,output [31:0] y);
	assign y={{16{a[15]}}, a};
endmodule


module flopr # (parameter WIDTH = 8)(input clk, reset,input [WIDTH-1:0] d,output reg [WIDTH-1:0] q);
	always @ (posedge clk, posedge reset)
		if (reset) q<=0;
		else q <= d;
endmodule



module mux2 # (parameter WIDTH = 8)(input [WIDTH-1:0] d0, d1,input s,output [WIDTH-1:0] y);
	assign y = s ? d1 : d0;
endmodule













//ALU: no changes
module alu(i_data_A, i_data_B, i_alu_control,o_result,o_zero_flag);

input [31:0] i_data_A;					// A operand 
input [31:0] i_data_B;					// B operand
output reg [31:0] o_result;				// ALU result
input [2:0] i_alu_control;				// Control signal

output wire o_zero_flag;				// Zero flag 
assign o_zero_flag = ~|o_result;




always @(*) begin
	// Start initialization:
	casex(i_alu_control)
		3'b010:	// ADD
			begin
				o_result = i_data_A + i_data_B;
			end
		3'b110:	// SUB
			begin
				o_result = i_data_A - i_data_B;
			end
		3'b000:	// AND
			begin
				o_result = i_data_A & i_data_B;
			end
		3'b001:	// OR 
			begin
				o_result = i_data_A | i_data_B;
			end
		3'b111:	// SLT
			begin
				o_result = i_data_A < i_data_B ? 32'h00000001 : 32'h00000000;	
			end
		3'b011:	// XOR 
			begin
				o_result = i_data_A ^ i_data_B;
			end
		3'b100:	// NOR
			begin
				o_result = ~(i_data_A | i_data_B);
			end
		default:
			begin
				o_result = {32{1'bx}};	// x-state, (nor 1, nor 0)
			end
	endcase
end

endmodule
