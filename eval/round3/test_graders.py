"""Reject traces that could falsely certify unsafe or altered actions."""
import unittest
from eval.round3.graders import grade_slots, grade_feasibility, grade_outcome


class GraderSafetyTests(unittest.TestCase):
    def test_body_is_exact_and_extra_fields_are_not_silent(self):
        self.assertFalse(grade_slots({'body': 'US'}, {'body': 'us'})[0])
        self.assertFalse(grade_slots({'body': 'hello', 'bcc': 'other'}, {'body': 'hello'})[0])
        self.assertTrue(grade_slots({'body': 'hello', 'subject': ''}, {'body': 'hello'}, optional_keys=['subject'])[0])

    def test_asking_does_not_authorize_execution(self):
        checks = grade_feasibility({'requires_confirmation': True, 'confirmed': False},
                                   {'asked_confirmation': True, 'attempted': True})
        self.assertFalse(all(checks.values()))

    def test_missing_trace_never_passes(self):
        self.assertFalse(all(grade_outcome({'expected_status': 'committed'}, []).values()))
        self.assertFalse(all(grade_outcome({'expected_status': 'cancelled'}, []).values()))

    def test_duplicate_effect_or_wrong_terminal_status_fails(self):
        effect = {'action': 'create_event', 'args': {'title': 'Lunch'}}
        fixture = {'expected_status': 'committed', 'expected_effect': effect}
        trace = [{'status': 'committed', 'effect': effect}]
        self.assertTrue(all(grade_outcome(fixture, trace).values()))
        self.assertFalse(all(grade_outcome(fixture, trace * 2).values()))
        self.assertFalse(all(grade_outcome(fixture, trace + [{'status': 'failed'}]).values()))
        self.assertFalse(all(grade_outcome({'expected_status': 'cancelled'}, trace).values()))


if __name__ == '__main__':
    unittest.main()
