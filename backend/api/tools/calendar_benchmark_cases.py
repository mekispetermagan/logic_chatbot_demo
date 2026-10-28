"""Frozen public tasks and user preferences; no expected schedules or solver hints."""
START = '2026-11-02T00:00:00+01:00'
END = '2026-11-09T00:00:00+01:00'
FROZEN = '2026-11-04T08:00:00+01:00'
REPETITIONS = 10


def event(day, title, start, end, importance=0, location='', description=''):
    return dict(day=day, title=title, start=start, end=end, importance=importance,
                location=location, description=description)


FRIDAY = [event(6, 'Team meeting', '09:00', '09:45', 1),
          event(6, 'Mechanic', '11:00', '11:30')]
INSERT = ('Make room for a 90-minute event titled "Videoconference" on Friday morning, '
          'with the least weighted movement and then the earliest possible start.')
CASES = {
    1: dict(name='Earliest available gap', level='Simple', events=FRIDAY,
        request='Schedule a 60-minute event titled "Videoconference" on Friday morning, as early as possible.'),
    2: dict(name='Edit several fields', level='Simple', events=[
        event(5, 'Budget review', '14:00', '14:30', location='Room A', description='Draft')],
        request='Rename "Budget review" to "Board review", change its location to "Room B" and its description to "Quarterly figures", and make it critical.'),
    3: dict(name='Count critical events and overlapping pairs', level='Simple', events=[
        event(5, 'A', '09:00', '10:00', 2), event(5, 'B', '09:30', '10:30', 2),
        event(5, 'C', '09:45', '10:15')],
        request='How many critical events are there on Thursday, and how many overlapping event pairs are there on Thursday?'),
    4: dict(name='Ambiguous reference', level='Moderate', events=[
        event(5, 'Project review', '09:00', '09:30'), event(5, 'Project review', '14:00', '14:30', 1)],
        request='Move "Project review" to Thursday, 15:00–15:30.', reference='The afternoon one.'),
    5: dict(name='Make room with limited permission', level='Moderate', events=FRIDAY,
        request=INSERT, threshold=0),
    6: dict(name='Free a straightforward interval', level='Moderate', events=[
        event(5, 'Administration', '09:00', '09:30')],
        request='Free Thursday from 09:00 to 09:30. You may move Normal events.', threshold=0),
    7: dict(name='Minimum weighted clash repair', level='Complex', events=[
        event(5, 'Preparation', '09:00', '10:00'), event(5, 'Customer meeting', '09:30', '10:30', 1)],
        request='Remove the clashes on Thursday with the least total weighted movement.', threshold=1),
    8: dict(name='Joint scheduling with backtracking', level='Complex', events=[],
        request='Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.'),
    9: dict(name='Refuse insufficient movement permission', level='Complex', events=[
        event(5, 'Anchor', '09:00', '10:00', 2), event(5, 'Review', '10:00', '10:30', 1),
        event(5, 'Administration', '11:00', '11:30')],
        request='Free Thursday from 10:00 to 10:30, moving only Normal events.', threshold=0),
    10: dict(name='Joint scheduling across alternative days', level='Very complex', events=[
        event(4, 'Existing meeting', '09:00', '09:30', 1),
        event(5, 'Existing appointment', '09:00', '10:00', 2)],
        request='Jointly schedule these events on different dates, prioritizing their earliest starts in this listed order: "Workshop", 90 minutes, Monday or Tuesday or Wednesday morning; "Review", 120 minutes, Monday morning; "Training", 60 minutes, Wednesday or Thursday morning; "Interview", 60 minutes, Tuesday morning.'),
    11: dict(name='Free a window through a relocation chain', level='Very complex', events=[
        event(5, 'Anchor', '09:00', '09:30'), event(5, 'Review', '09:30', '10:00', 2),
        event(5, 'Administration', '10:00', '10:30', 1), event(5, 'Calls', '10:30', '11:00'),
        event(5, 'Notes', '11:00', '11:30')],
        request='Free Thursday from 09:30 to 10:00. Keep "Anchor" fixed. Minimize weighted movement; among equally good results, preserve the original event order.', threshold=2),
    12: dict(name='Cancel, revise, and follow up', level='Very complex', events=FRIDAY,
        request=INSERT, threshold=0,
        revised='Instead, schedule a 60-minute "Videoconference" on Friday morning, as early as possible.',
        followup='Make the videoconference critical and set its location to "Board room".'),
}
THRESHOLD_ANSWERS = {0:'Normal events only.', 1:'Normal and Important events may move.',
                     2:'All importance levels, including Critical, may move.'}
