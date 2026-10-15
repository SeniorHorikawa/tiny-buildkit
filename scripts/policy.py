import omvll
from functools import lru_cache


class Policy(omvll.ObfuscationConfig):

    def flatten_cfg(self, mod, func):
        return True

    def obfuscate_string(self, mod, func, string):
        return omvll.StringEncOptGlobal()

    def obfuscate_constants(self, mod, func):
        return omvll.OpaqueConstantsBool(True)

    def obfuscate_arithmetic(self, mod, func):
        return omvll.ArithmeticOpt(3)

    def basic_block_split(self, mod, func):
        return omvll.BasicBlockSplitWithProbability(25)

    def basic_block_duplicate(self, mod, func):
        return omvll.BasicBlockDuplicateWithProbability(10)


@lru_cache(maxsize=1)
def omvll_get_config() -> omvll.ObfuscationConfig:
    omvll.config.shuffle_functions = True
    return Policy()
