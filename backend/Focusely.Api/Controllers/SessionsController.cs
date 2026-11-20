using System.Security.Claims;
using Focusely.Api.Data;
using Focusely.Api.Dtos;
using Focusely.Api.Models;
using Focusely.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Focusely.Api.Controllers;

[ApiController, Route("api/sessions"), Authorize]
public class SessionsController(AppDbContext db) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirstValue("sub")!);

    private Task<StudySession?> GetActive() =>
        db.StudySessions.FirstOrDefaultAsync(s => s.UserId == UserId && s.EndedAtUtc == null);

    [HttpPost("start")]
    public async Task<ActionResult<SessionDto>> Start(StartSessionDto dto)
    {
        // Idempotence : meme Id renvoye par le client => on ne recree pas
        var existing = await db.StudySessions
            .FirstOrDefaultAsync(s => s.Id == dto.Id && s.UserId == UserId);
        if (existing is not null) return Ok(existing.ToDto());

        // RG03 : pas de sessions simultanees
        if (await GetActive() is not null)
            return Conflict("Une seance est deja en cours.");

        if (dto.SubjectId is not null &&
            !await db.Subjects.AnyAsync(x => x.Id == dto.SubjectId && x.UserId == UserId))
            return BadRequest("Matiere inconnue.");

        var s = new StudySession
        {
            Id = dto.Id == Guid.Empty ? Guid.NewGuid() : dto.Id,
            UserId = UserId,
            SubjectId = dto.SubjectId,
            Mode = dto.Mode,
            TargetSeconds = dto.TargetSeconds,
            StartedAtUtc = DateTime.UtcNow          // RG02 : l'heure du serveur fait foi
        };
        db.StudySessions.Add(s);
        await db.SaveChangesAsync();
        return Ok(s.ToDto());
    }

    [HttpPost("pause")]
    public async Task<ActionResult<SessionDto>> Pause()
    {
        var s = await GetActive();
        if (s is null) return NotFound("Aucune seance active.");
        if (s.PausedAtUtc is not null) return BadRequest("Deja en pause.");
        s.PausedAtUtc = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return Ok(s.ToDto());
    }

    [HttpPost("resume")]
    public async Task<ActionResult<SessionDto>> Resume()
    {
        var s = await GetActive();
        if (s is null) return NotFound("Aucune seance active.");
        if (s.PausedAtUtc is null) return BadRequest("La seance n'est pas en pause.");
        s.PausedSeconds += (int)(DateTime.UtcNow - s.PausedAtUtc.Value).TotalSeconds;
        s.PausedAtUtc = null;
        await db.SaveChangesAsync();
        return Ok(s.ToDto());
    }

    [HttpPost("stop")]
    public async Task<ActionResult<SessionDto>> Stop()
    {
        var s = await GetActive();
        if (s is null) return NotFound("Aucune seance active.");
        var now = DateTime.UtcNow;
        if (s.PausedAtUtc is not null)      // finaliser la pause en cours
        {
            s.PausedSeconds += (int)(now - s.PausedAtUtc.Value).TotalSeconds;
            s.PausedAtUtc = null;
        }
        s.EndedAtUtc = now;
        s.StudySeconds = s.ComputeStudySeconds(now);
        s.IsValidated = s.StudySeconds >= Focusely.Api.Services.SessionExtensions.MinValidSeconds;   // RG01
        await db.SaveChangesAsync();
        return Ok(s.ToDto());
    }

    // Recuperation apres fermeture/redemarrage de l'app
    [HttpGet("active")]
    public async Task<ActionResult<SessionDto>> Active()
    {
        var s = await GetActive();
        return s is null ? NoContent() : Ok(s.ToDto());
    }

    [HttpGet("history")]
    public async Task<ActionResult<List<SessionDto>>> History([FromQuery] int take = 50)
    {
        var list = await db.StudySessions
            .Where(s => s.UserId == UserId && s.EndedAtUtc != null)
            .OrderByDescending(s => s.StartedAtUtc)
            .Take(Math.Clamp(take, 1, 200))
            .ToListAsync();
        return Ok(list.Select(s => s.ToDto()).ToList());
    }
}
