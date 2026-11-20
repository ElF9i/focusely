namespace Focusely.Api.Dtos;

public record DayStat(string Date, int Seconds);
public record SubjectStat(Guid? SubjectId, string Name, string Color, string Emoji, int Seconds);

public record StatsDto(
    int TodaySeconds, int WeekSeconds, int MonthSeconds, int TotalSeconds, int Sessions,
    int Streak, int Xp, int Level, int LevelXp, int NextLevelXp,
    List<DayStat> Days, List<SubjectStat> BySubject);
