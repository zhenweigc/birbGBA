app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.Path
import pf.Stdout
import pf.OsStr
import src/Machine
import src/Cpu

main! : List(OsStr) => Try({}, _)
main! = |args| {
	(bios_arg, rom_arg, budget_arg) = match args {
		[a, b, c] => (a, b, c)
		_ => return Err(ExpectedBiosRomBudgetArgs)
	}

	bios_path = Path.from_os_str(bios_arg)
	rom_path = Path.from_os_str(rom_arg)
	bios = bios_path.read_bytes!()?
	rom = rom_path.read_bytes!()?
	num_of_actions = U32.from_str(OsStr.to_str_try(budget_arg)?)?

	m = Machine.init(bios, rom)?
	done = Machine.run_with_budget(m, num_of_actions)?
	c = Machine.get_cpu(done)

	Stdout.line!("PC: ${Cpu.getPC(c).to_str()}, cycles: ${Machine.get_time(done).to_str()}")?
	Ok({})
}
