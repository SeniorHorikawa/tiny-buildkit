import os
import omvll
from functools import lru_cache

LEVEL = int(os.environ.get("OBF_LEVEL", "3") or "3")
_raw_seed = os.environ.get("OBF_SEED", "")
EXCLUDE_MODULES = []
EXCLUDE_FUNCS = []
INCLUDE_FUNCS = []

if _raw_seed.lower() == "random":
    SEED = int.from_bytes(os.urandom(4), "little")
elif _raw_seed:
    SEED = int(_raw_seed)
else:
    SEED = None


class Policy(omvll.ObfuscationConfig):

    def _cfg(self, mod, func, probability):
        return omvll.ObfuscationConfig.default_config(
            self, mod, func, EXCLUDE_MODULES, EXCLUDE_FUNCS, INCLUDE_FUNCS, probability
        )

    def flatten_cfg(self, mod, func):
        return omvll.ControlFlowFlatteningOpt(self._cfg(mod, func, 100))

    def break_control_flow(self, mod, func):
        return omvll.BreakControlFlowOpt(self._cfg(mod, func, 15 if LEVEL >= 3 else 5))

    def obfuscate_string(self, mod, func, string):
        return omvll.StringEncOptGlobal()

    def obfuscate_constants(self, mod, func):
        return omvll.OpaqueConstantsBool(True)

    def obfuscate_arithmetic(self, mod, func):
        return omvll.ArithmeticOpt(4 if LEVEL >= 3 else 3)

    def obfuscate_variable_access(self, mod, func, var):
        return omvll.VarAccessOpt(self._cfg(mod, func, 10))

    def obfuscate_struct_access(self, mod, func, struct):
        return omvll.StructAccessOpt(self._cfg(mod, func, 10))

    def basic_block_split(self, mod, func):
        return omvll.BasicBlockSplitWithProbability(60 if LEVEL >= 3 else 40)

    def basic_block_duplicate(self, mod, func):
        return omvll.BasicBlockDuplicateWithProbability(30 if LEVEL >= 3 else 20)

    def function_outline(self, mod, func):
        return omvll.FunctionOutlineWithProbability(15 if LEVEL >= 3 else 10)

    def shuffle_ops(self, mod, func):
        if LEVEL < 2:
            return False
        return omvll.ShuffleOpsOpt(min_block_size=4 if LEVEL >= 3 else 8)

    def indirect_branch(self, mod, func):
        if LEVEL < 3:
            return False
        return self._cfg(mod, func, 100)

    def indirect_call(self, mod, func):
        if LEVEL < 2:
            return False
        return self._cfg(mod, func, 100 if LEVEL >= 3 else 60)

    def anti_hooking(self, mod, func):
        if LEVEL < 2:
            return False
        return omvll.AntiHookOpt(True)


@lru_cache(maxsize=1)
def omvll_get_config() -> omvll.ObfuscationConfig:
    omvll.config.shuffle_functions = True
    if SEED is not None:
        omvll.config.probability_seed = SEED
    if LEVEL >= 3:
        omvll.config.pass_phases = {
            omvll.Pass.AntiHook: {omvll.Phase.Early},
            omvll.Pass.FunctionOutline: {omvll.Phase.Early},
            omvll.Pass.StringEncoding: {omvll.Phase.Early, omvll.Phase.Last},
            omvll.Pass.OpaqueFieldAccess: {omvll.Phase.Early},
            omvll.Pass.BasicBlockSplit: {omvll.Phase.Early},
            omvll.Pass.ShuffleOps: {omvll.Phase.Early},
            omvll.Pass.BasicBlockDuplicate: {omvll.Phase.Early},
            omvll.Pass.ControlFlowFlattening: {omvll.Phase.Early},
            omvll.Pass.BreakControlFlow: {omvll.Phase.Early},
            omvll.Pass.OpaqueConstants: {omvll.Phase.Early},
            omvll.Pass.Arithmetic: {omvll.Phase.Early},
            omvll.Pass.IndirectCall: {omvll.Phase.Last},
            omvll.Pass.IndirectBranch: {omvll.Phase.Last},
        }
    return Policy()
