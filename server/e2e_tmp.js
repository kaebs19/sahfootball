process.env.DATABASE_URL = 'postgres://localhost/fant';
require('dotenv').config({ override: false });
process.env.DATABASE_URL = 'postgres://localhost/fant';
const db = require('./src/config/db');
const fantasyRepo = require('./src/repositories/fantasyRepo');
const squadService = require('./src/services/fantasySquadService');
const fantasyScoring = require('./src/services/fantasyScoring');

const q = (sql, p) => db.query(sql, p);
(async () => {
  await q(`TRUNCATE fantasy_round_players, fantasy_round_entries, fantasy_squad_players,
           fantasy_squads, player_fixture_stats, players, fixtures, teams, leagues, users
           RESTART IDENTITY CASCADE`);
  await q(`INSERT INTO leagues (id,name_en,season,in_app,enabled) VALUES (307,'Roshn',2026,true,true)`);
  const { rows: [user] } = await q(
    `INSERT INTO users (email, password_hash, display_name) VALUES ('t@t.com','x','مدرّب') RETURNING id`);

  for (let t = 1; t <= 6; t++) await q(`INSERT INTO teams (id,name_en) VALUES ($1,$2)`, [t, `Club${t}`]);

  // ١٥ لاعباً: ٣ من كل نادٍ من الأندية ١..٥
  let pid = 1; const P = { Goalkeeper: [], Defender: [], Midfielder: [], Attacker: [] };
  const mk = async (position, team, price) => {
    await q(`INSERT INTO players (id,team_id,league_id,season,name_en,position,price,available)
             VALUES ($1,$2,307,2026,$3,$4,$5,true)`, [pid, team, `P${pid}`, position, price]);
    P[position].push(pid); return pid++;
  };
  await mk('Goalkeeper',1,5); await mk('Goalkeeper',2,4);
  for (const t of [1,2,3,4,5]) await mk('Defender', t, 5);
  for (const t of [1,2,3,4,5]) await mk('Midfielder', t, 6);
  for (const t of [3,4,5]) await mk('Attacker', t, 8);

  const picks = [
    ...P.Goalkeeper.map((id,i)=>({player_id:id,on_bench:i>0})),
    ...P.Defender.map((id,i)=>({player_id:id,on_bench:i>3})),
    ...P.Midfielder.map((id,i)=>({player_id:id,on_bench:i>3})),
    ...P.Attacker.map((id,i)=>({player_id:id,on_bench:i>1})),
  ];
  picks[2].is_captain = true; picks[7].is_vice = true;

  const market = await fantasyRepo.market(307, 2026, {});
  console.log('السوق:', market.length, 'لاعباً');
  const byId = new Map((await fantasyRepo.playersByIds(picks.map(p=>p.player_id))).map(r=>[r.player_id,r]));
  const v = squadService.validateSquad(picks, byId, { formation:'4-4-2', clubTeamId:1, leagueId:307 });
  const benchOrder = new Map(v.bench.map((b,i)=>[b.player_id,i]));
  await fantasyRepo.saveSquad({ userId:user.id, leagueId:307, season:2026, clubTeamId:1,
    formation:'4-4-2', name:'فريق التجربة', budgetLeft:v.budget_left,
    rows: v.rows.map(r=>({...r, bench_order: benchOrder.get(r.player_id) ?? 0})) });
  const squad = await fantasyRepo.findSquad(user.id, 307, 2026);
  console.log('التشكيلة محفوظة: متبقٍّ', squad.budget_left, '— لاعبون', (await fantasyRepo.squadPlayers(squad.id)).length);

  // جولة بمباراتين انتهتا
  const now = new Date();
  for (const [id,h,a,gh,ga] of [[900,1,2,2,0],[901,3,4,1,1]])
    await q(`INSERT INTO fixtures (id,league_id,season,round,home_team_id,away_team_id,kickoff_at,status,goals_home,goals_away)
             VALUES ($1,307,2026,'Regular Season - 1',$2,$3,$4,'finished',$5,$6)`, [id,h,a,now,gh,ga]);

  const locked = await fantasyRepo.lockRound(307, 2026, 'Regular Season - 1');
  console.log('جُمّدت تشكيلات:', locked);

  // إحصاء: الكابتن (مدافع نادي ١) سجّل وشباك نظيفة
  const stat = (fx, pl, team, o={}) => q(
    `INSERT INTO player_fixture_stats (fixture_id,player_id,team_id,minutes,goals,assists,conceded,saves,yellow,red,own_goals,pen_scored,pen_missed,pen_saved)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,0,0,0,0,0,0)`,
    [fx, pl, team, o.minutes ?? 90, o.goals ?? 0, o.assists ?? 0, o.conceded ?? 0, o.saves ?? 0]);
  await stat(900, P.Goalkeeper[0], 1, { saves: 3 });
  await stat(900, P.Defender[0], 1, { goals: 1 });          // الكابتن
  await stat(900, P.Defender[1], 2, { conceded: 2 });
  await stat(901, P.Defender[2], 3, { conceded: 1 });
  await stat(901, P.Defender[3], 4, { conceded: 1 });
  await stat(900, P.Midfielder[0], 1, { assists: 1 });
  await stat(900, P.Midfielder[1], 2, { conceded: 2 });
  await stat(901, P.Midfielder[2], 3, { conceded: 1 });
  // المدافع/الوسط الرابع الأساسي والمهاجمان لم يلعبوا → تبديل تلقائي
  await stat(901, P.Attacker[2], 5, { minutes: 90, goals: 1 });   // مهاجم بديل دخل
  await stat(901, P.Midfielder[4], 5, { minutes: 90 });           // وسط بديل دخل

  const { settleFinishedRounds } = require('./src/jobs/settleFantasy');
  const n = await settleFinishedRounds();
  console.log('سُوّيت تشكيلات:', n);

  const { rows: entry } = await q(`SELECT points, settled_at IS NOT NULL AS done FROM fantasy_round_entries`);
  console.log('نقاط الجولة:', entry[0].points, '| مسوّاة:', entry[0].done);
  const { rows: rp } = await q(
    `SELECT rp.player_id, p.position, rp.points, rp.multiplier, rp.auto_subbed, rp.on_bench
       FROM fantasy_round_players rp JOIN players p ON p.id=rp.player_id
      WHERE rp.points <> 0 OR rp.auto_subbed ORDER BY rp.points DESC`);
  for (const r of rp) console.log(`   #${r.player_id} ${r.position.slice(0,3)} ${r.points} نقطة ×${r.multiplier}${r.auto_subbed?' (دخل بديلاً)':''}${r.on_bench?' [دكّة]':''}`);
  const lb = await fantasyRepo.leaderboard(307, 2026);
  console.log('العرش:', lb.map(e=>`${e.rank}. ${e.name} — ${e.total_points}`).join(' | '));
  await db.pool.end();
})().catch(e => { console.log('FAILED:', e.message, e.stack?.split('\n')[1]); process.exit(1); });
