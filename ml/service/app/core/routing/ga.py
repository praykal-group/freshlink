"""Genetic DVRPTW (Section 8, DEAP).

Chromosome: permutation of range(F + V - 1); values < F are free stops, values >= F are the V-1
separators that split the permutation into V vehicle routes (stop order + vehicle split in one
genome). Fixed prefixes (REPLAN) are prepended during decoding and never move.

Operators: ordered crossover (p 0.8), swap mutation (p 0.1), tournament 3, pop 100, gens 200,
2 elites, early stop after 30 generations without gain, hard time limit 8 s. The population is
seeded with a time-window-aware cheapest-insertion solution. Memetic polish (D-69): relocate +
2-opt local search on the seed and on the final best, inside the same time limit.
"""

import random
import time
from dataclasses import dataclass
from typing import List, Optional, Sequence

from deap import base, creator, tools

from .problem import Problem, Solution, evaluate, evaluate_route

POP = 100
GENS = 200
CXPB = 0.8
MUTPB = 0.1
TOURNAMENT = 3
ELITES = 2
PATIENCE = 30
TIME_LIMIT_S = 8.0

if not hasattr(creator, "IccmsFitnessMin"):
    creator.create("IccmsFitnessMin", base.Fitness, weights=(-1.0,))
    creator.create("IccmsIndividual", list, fitness=creator.IccmsFitnessMin)


@dataclass
class GaResult:
    solution: Solution
    generations: int
    stopped_by: str  # "generations" | "patience" | "time"
    seed_fitness: float


def decode(p: Problem, genome: Sequence[int], free: Sequence[int]) -> List[List[int]]:
    f = len(free)
    routes: List[List[int]] = [list(p.fixed_prefix.get(v, [])) for v in range(len(p.vehicles))]
    v = 0
    for g in genome:
        if g >= f:
            v += 1
        else:
            routes[v].append(free[g])
    return routes


def encode(routes: List[List[int]], p: Problem, free: Sequence[int]) -> List[int]:
    pos = {s: i for i, s in enumerate(free)}
    f = len(free)
    genome: List[int] = []
    for v, r in enumerate(routes):
        prefix_len = len(p.fixed_prefix.get(v, []))
        genome.extend(pos[s] for s in r[prefix_len:])
        if v < len(routes) - 1:
            genome.append(f + v)
    return genome


def cheapest_insertion(p: Problem) -> List[List[int]]:
    """Insert stops (earliest window end first) where the route cost grows least. Respects must_vehicle."""
    routes: List[List[int]] = [list(p.fixed_prefix.get(v, [])) for v in range(len(p.vehicles))]
    costs = [evaluate_route(p, v, r).cost for v, r in enumerate(routes)]
    prefix = {v: len(p.fixed_prefix.get(v, [])) for v in range(len(p.vehicles))}
    order = sorted(p.free_stops, key=lambda s: (p.stops[s].window_end if p.stops[s].window_end is not None else float("inf"), -p.stops[s].demand))
    for s in order:
        must = p.stops[s].must_vehicle
        best = None
        for v in range(len(p.vehicles)):
            if must is not None and v != must:
                continue
            r = routes[v]
            for pos in range(prefix[v], len(r) + 1):
                cand = r[:pos] + [s] + r[pos:]
                delta = evaluate_route(p, v, cand).cost - costs[v]
                if best is None or delta < best[0]:
                    best = (delta, v, pos)
        assert best is not None
        _, v, pos = best
        routes[v].insert(pos, s)
        costs[v] = evaluate_route(p, v, routes[v]).cost
    return routes


def local_search(p: Problem, routes: List[List[int]], deadline: float) -> List[List[int]]:
    """Polish (memetic step, D-69): first-improvement relocate (any stop to its best position on any
    route) and intra-route 2-opt, repeated until no gain or the deadline. Fixed prefixes never move;
    must_vehicle stops only move within their vehicle."""
    routes = [list(r) for r in routes]
    prefix = {v: len(p.fixed_prefix.get(v, [])) for v in range(len(routes))}
    costs = [evaluate_route(p, v, r).cost for v, r in enumerate(routes)]
    improved = True
    while improved and time.perf_counter() < deadline:
        improved = False
        # relocate
        for v in range(len(routes)):
            i = prefix[v]
            while i < len(routes[v]):
                if time.perf_counter() >= deadline:
                    return routes
                s = routes[v][i]
                must = p.stops[s].must_vehicle
                without = routes[v][:i] + routes[v][i + 1 :]
                base_without = evaluate_route(p, v, without).cost
                best = None
                for w in range(len(routes)):
                    if must is not None and w != must:
                        continue
                    target = without if w == v else routes[w]
                    base = base_without if w == v else costs[w]
                    for pos in range(prefix[w], len(target) + 1):
                        if w == v and pos == i:
                            continue
                        cand = target[:pos] + [s] + target[pos:]
                        gain = (costs[v] + (costs[w] if w != v else 0)) - (base_without + evaluate_route(p, w, cand).cost if w != v else evaluate_route(p, w, cand).cost)
                        if gain > 1e-6 and (best is None or gain > best[0]):
                            best = (gain, w, pos)
                if best:
                    _, w, pos = best
                    if w == v:
                        routes[v] = without[:pos] + [s] + without[pos:]
                    else:
                        routes[v] = without
                        routes[w] = routes[w][:pos] + [s] + routes[w][pos:]
                        costs[w] = evaluate_route(p, w, routes[w]).cost
                    costs[v] = evaluate_route(p, v, routes[v]).cost
                    improved = True
                else:
                    i += 1
        # intra-route 2-opt
        for v in range(len(routes)):
            r = routes[v]
            for a in range(prefix[v], len(r) - 1):
                for b in range(a + 1, len(r)):
                    if time.perf_counter() >= deadline:
                        return routes
                    cand = r[:a] + r[a : b + 1][::-1] + r[b + 1 :]
                    c = evaluate_route(p, v, cand).cost
                    if c < costs[v] - 1e-6:
                        routes[v], costs[v], r = cand, c, cand
                        improved = True
    return routes


def mut_swap(ind: List[int], rng: random.Random) -> List[int]:
    if len(ind) >= 2:
        i, j = rng.sample(range(len(ind)), 2)
        ind[i], ind[j] = ind[j], ind[i]
    return ind


def solve(
    p: Problem,
    seed: Optional[int] = None,
    time_limit_s: float = TIME_LIMIT_S,
    pop_size: int = POP,
    generations: int = GENS,
) -> GaResult:
    started = time.perf_counter()
    rng = random.Random(seed)
    free = p.free_stops
    n_genes = len(free) + len(p.vehicles) - 1

    seed_routes = cheapest_insertion(p)
    seed_fitness = evaluate(p, seed_routes).fitness
    # Budget: up to 25 % polishing the seed, the GA, and whatever is left polishing the best.
    seed_routes = local_search(p, seed_routes, started + 0.25 * time_limit_s)
    seed_solution = evaluate(p, seed_routes)
    if len(free) <= 1 or len(p.vehicles) == 0:
        return GaResult(evaluate(p, seed_routes, keep_visits=True), 0, "generations", seed_fitness)

    def fitness(genome) -> float:
        return evaluate(p, decode(p, genome, free)).fitness

    def new_individual(genome):
        ind = creator.IccmsIndividual(genome)
        ind.fitness.values = (fitness(ind),)
        return ind

    seed_genome = encode(seed_routes, p, free)
    population = [new_individual(seed_genome)]
    # A few light mutations of the seed keep its structure in the gene pool.
    for _ in range(min(10, pop_size - 1)):
        population.append(new_individual(mut_swap(list(seed_genome), rng)))
    while len(population) < pop_size:
        g = list(range(n_genes))
        rng.shuffle(g)
        population.append(new_individual(g))

    best = min(population, key=lambda i: i.fitness.values[0])
    best_fit = best.fitness.values[0]
    stale = 0
    gen = 0
    stopped_by = "generations"
    random.seed(rng.random())  # DEAP operators use the global RNG
    for gen in range(1, generations + 1):
        if time.perf_counter() - started > time_limit_s:
            stopped_by = "time"
            break
        elites = [creator.IccmsIndividual(list(e)) for e in tools.selBest(population, ELITES)]
        for e, src in zip(elites, tools.selBest(population, ELITES)):
            e.fitness.values = src.fitness.values
        offspring = [creator.IccmsIndividual(list(i)) for i in tools.selTournament(population, pop_size - ELITES, tournsize=TOURNAMENT)]
        for a, b in zip(offspring[::2], offspring[1::2]):
            if rng.random() < CXPB:
                tools.cxOrdered(a, b)
        for ind in offspring:
            if rng.random() < MUTPB:
                mut_swap(ind, rng)
            ind.fitness.values = (fitness(ind),)
        population = elites + offspring
        gen_best = min(population, key=lambda i: i.fitness.values[0])
        if gen_best.fitness.values[0] < best_fit - 1e-9:
            best, best_fit, stale = gen_best, gen_best.fitness.values[0], 0
        else:
            stale += 1
            if stale >= PATIENCE:
                stopped_by = "patience"
                break

    best_routes = local_search(p, decode(p, best, free), started + time_limit_s)
    solution = evaluate(p, best_routes, keep_visits=True)
    return GaResult(solution, gen, stopped_by, seed_fitness)
