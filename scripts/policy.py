import omvll
from functools import lru_cache

SENSITIVE = []


class Policy(omvll.ObfuscationConfig):

    def flatten_cfg(self, mod, func):
        return True

    def break_control_flow(self, mod, func):
        return omvll.BreakControlFlowOpt(
            omvll.ObfuscationConfig.default_config(self, mod, func, [], [], SENSITIVE, 5)
        )

    def obfuscate_string(self, mod, func, string):
        return omvll.StringEncOptGlobal()

    def obfuscate_constants(self, mod, func):
        return omvll.OpaqueConstantsBool(True)

    def obfuscate_arithmetic(self, mod, func):
        return omvll.ArithmeticOpt(3)

    def obfuscate_variable_access(self, mod, func, var):
        return omvll.VarAccessOpt(
            omvll.ObfuscationConfig.default_config(self, mod, func, [], [], SENSITIVE, 10)
        )

    def obfuscate_struct_access(self, mod, func, struct):
        return omvll.StructAccessOpt(
            omvll.ObfuscationConfig.default_config(self, mod, func, [], [], SENSITIVE, 10)
        )

    def basic_block_split(self, mod, func):
        return omvll.BasicBlockSplitWithProbability(40)

    def basic_block_duplicate(self, mod, func):
        return omvll.BasicBlockDuplicateWithProbability(20)

    def function_outline(self, mod, func):
        return omvll.FunctionOutlineWithProbability(10)


@lru_cache(maxsize=1)
def omvll_get_config() -> omvll.ObfuscationConfig:
    omvll.config.shuffle_functions = True
    return Policy()
