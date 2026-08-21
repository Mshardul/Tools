import unittest

from port_tool import parse_lsof_pids


class PortToolTests(unittest.TestCase):
    def test_parse_lsof_pids(self):
        sample = (
            "COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME\n"
            "node    1234 me   23u  IPv4 0xabc      0t0  TCP *:3000 (LISTEN)\n"
            "node    1234 me   24u  IPv6 0xdef      0t0  TCP *:3000 (LISTEN)\n"
            "python  5678 me   10u  IPv4 0xghi      0t0  TCP *:3000 (LISTEN)\n"
        )
        self.assertEqual(parse_lsof_pids(sample), [1234, 5678])

    def test_parse_empty(self):
        self.assertEqual(parse_lsof_pids(""), [])
        self.assertEqual(parse_lsof_pids("COMMAND PID USER\n"), [])


if __name__ == "__main__":
    unittest.main()
