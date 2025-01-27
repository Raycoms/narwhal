from utils import BenchError, Print, PathMaker, progress_bar
from logs import LogParser, ParseError

LogParser.process(PathMaker.logs_path(), faults=0).print(PathMaker.result_file(
                            0,
                            1000,
                            1,
                            True,
                            1000,
                            32,
                        ))


