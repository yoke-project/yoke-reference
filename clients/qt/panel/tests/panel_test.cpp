// The panel's cases, each reported in the form the record writer reads: `pass  <id>`, or `FAIL  <id> — <why>`.
#include <fstream>
#include <functional>
#include <iostream>
#include <sstream>
#include <stdexcept>

#include <QApplication>
#include <QLabel>
#include <QPushButton>

#include "picture.hpp"
#include "window.hpp"

namespace v1 = yoke::iface::v1;

namespace {

struct Failed : std::runtime_error {
    using std::runtime_error::runtime_error;
};

void require(bool cond, const std::string &why) {
    if (!cond) {
        throw Failed(why);
    }
}

v1::Record unit(const std::string &id, const std::string &state, std::initializer_list<std::string> streams = {},
                std::initializer_list<std::string> queries = {}, std::initializer_list<std::string> commands = {},
                const std::string &condition = "") {
    v1::Record r;
    auto *u = r.mutable_unit();
    u->mutable_declared()->set_identity(id);
    u->mutable_declared()->set_kind("plugin");
    u->mutable_observed()->set_state(state);
    if (!condition.empty()) {
        u->mutable_observed()->mutable_condition()->set_line(condition);
    }
    for (const auto &s : streams) u->mutable_addressed()->add_streams(s);
    for (const auto &q : queries) u->mutable_addressed()->add_queries(q);
    for (const auto &c : commands) u->mutable_addressed()->add_commands(c);
    return r;
}

v1::Record channel(bool suspended) {
    v1::Record r;
    auto *c = r.mutable_channel();
    c->mutable_declared()->set_name("panel");
    c->mutable_declared()->set_projection("local");
    c->mutable_declared()->set_address_class("local-socket");
    c->mutable_declared()->set_clients("single");
    c->mutable_observed()->set_suspended(suspended);
    if (suspended) {
        c->mutable_observed()->set_grade("read-only");
        c->mutable_observed()->set_by("remote");
    }
    return r;
}

v1::Snapshot opening() {
    v1::Snapshot s;
    s.set_at(4);
    s.add_records()->mutable_instance()->set_ready(true);
    *s.add_records() = channel(false);
    *s.add_records() = unit("acquire", "Starting");
    *s.add_records() = unit("provision-store", "Completed");
    return s;
}

v1::Subscribed event(std::uint64_t seq, const std::string &kind, const std::string &identity) {
    v1::Subscribed d;
    d.mutable_event()->set_seq(seq);
    d.mutable_event()->mutable_subject()->set_kind(kind);
    d.mutable_event()->mutable_subject()->set_identity(identity);
    return d;
}

// std: yoke-reference:the-panel.01
void the_picture_is_the_opening_held_by_subject() {
    panel::Picture p(opening());
    require(p.at() == 4 && p.applied() == 4, "the picture is not at 4");
    std::vector<std::string> keys;
    for (const auto &r : p.records()) keys.push_back(panel::key(r));
    require((keys == std::vector<std::string>{"instance", "channel/panel", "unit/acquire", "unit/provision-store"}),
            "the picture holds the wrong subjects");
    require(p.instance() && p.instance()->ready() && p.channel() && p.units().size() == 2,
            "the picture does not hold the instance, the channel and the two units");
}

// std: yoke-reference:the-panel.02
void an_event_reads_its_subject_again_and_only_what_is_applied_is_confirmed() {
    panel::Picture p(opening());
    auto read = [](const std::string &kind, const std::string &identity) -> std::vector<v1::Record> {
        if (kind == "unit" && identity == "acquire") return {unit("acquire", "Running")};
        throw std::runtime_error("cannot be read");
    };
    require(p.apply(event(5, "unit", "acquire"), read), "the first event changed nothing");
    require(p.units()[0]->observed().state() == "Running" && p.applied() == 5, "acquire is not Running at 5");
    p.apply(event(6, "unit", "gone"), read);
    require(p.applied() == 5, "a subject not read was confirmed past");
    v1::Subscribed overflow;
    overflow.mutable_overflow()->set_at(9);
    *overflow.mutable_overflow()->add_records() = channel(false);
    require(p.apply(overflow, read), "the overflow changed nothing");
    require(p.records().size() == 1 && p.channel() && p.applied() == 9, "the overflow did not replace the picture");
}

struct Nothing : panel::Acts {
    std::string command(const std::string &, const std::string &, const std::string &) override { return ""; }
    std::string ask(const std::string &, const std::string &, const std::string &) override { return ""; }
    std::string start(const std::string &, const std::string &) override { return ""; }
    std::string stop(const std::string &, const std::string &) override { return ""; }
    std::string watch(const std::string &, const std::string &, std::function<void(const std::string &)>) override {
        return "";
    }
    std::string reclaim() override { return ""; }
};

// std: yoke-reference:the-panel.03
void the_window_is_composed_from_the_picture() {
    v1::Snapshot s;
    s.set_at(1);
    *s.add_records() = channel(true);
    *s.add_records() = unit("acquire", "Running", {"station.spectra"}, {}, {}, "acquiring");
    *s.add_records() = unit("pipeline", "Running", {}, {"spectrum.identify"}, {"pipeline.reindex"});
    *s.add_records() = unit("provision-store", "Completed");
    Nothing acts;
    panel::Window w(acts);
    w.draw(panel::Picture(s));
    auto label = [&](const char *name) {
        auto *l = w.findChild<QLabel *>(name);
        return l ? l->text().toStdString() : std::string("(none)");
    };
    auto button = [&](const char *name) { return w.findChild<QPushButton *>(name) != nullptr; };
    std::string c = label("channel");
    require(c.find("suspended, read-only") != std::string::npos && c.find("remote prevails") != std::string::npos,
            "the channel line says " + c);
    require(!w.findChild<QPushButton *>("reclaim")->isHidden(), "reclaiming is not offered");
    require(label("state:acquire") == "Running · acquiring", "acquire's state says " + label("state:acquire"));
    require(button("start:acquire:station.spectra") && button("stop:acquire:station.spectra") &&
                button("watch:acquire:station.spectra"),
            "acquire's stream has no start, stop and watch");
    require(button("ask:pipeline:spectrum.identify") && button("command:pipeline:pipeline.reindex"),
            "pipeline's question and command have no buttons");
    require(label("nothing:provision-store").find("nothing this channel may address") != std::string::npos,
            "provision-store's card says " + label("nothing:provision-store"));
    for (const char *file : {"/src/picture.cpp", "/src/picture.hpp", "/src/window.cpp", "/src/window.hpp", "/src/main.cpp"}) {
        std::ifstream in(std::string(SOURCE_DIR) + file);
        std::stringstream text;
        text << in.rdbuf();
        for (const char *named : {"acquire", "pipeline", "station.", "spectr", "com.yoke"}) {
            require(text.str().find(named) == std::string::npos, std::string(file) + " names " + named);
        }
    }
}

} // namespace

int main(int argc, char **argv) {
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QApplication app(argc, argv);
    int failed = 0;
    for (auto [id, run] : std::initializer_list<std::pair<const char *, void (*)()>>{
             {"yoke-reference:the-panel.01", the_picture_is_the_opening_held_by_subject},
             {"yoke-reference:the-panel.02", an_event_reads_its_subject_again_and_only_what_is_applied_is_confirmed},
             {"yoke-reference:the-panel.03", the_window_is_composed_from_the_picture},
         }) {
        try {
            run();
            std::cout << "pass  " << id << "\n";
        } catch (const std::exception &e) {
            std::cout << "FAIL  " << id << " — " << e.what() << "\n";
            failed = 1;
        }
    }
    return failed;
}
