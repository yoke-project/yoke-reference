#include "window.hpp"

#include <set>
#include <thread>

#include <QApplication>
#include <QHBoxLayout>
#include <QLineEdit>
#include <QMetaObject>
#include <QPushButton>

namespace panel {

std::string said(const std::exception &e) {
    if (auto *s = dynamic_cast<const yoke::iface::Suspended *>(&e)) {
        return "refused " + s->code() + " (" + s->grade() + (s->by().empty() ? "" : ", by " + s->by()) + ")";
    }
    if (auto *r = dynamic_cast<const yoke::Refusal *>(&e)) {
        return "refused " + r->code() + ": " + r->what();
    }
    return e.what();
}

Window::Window(Acts &acts, QWidget *parent) : QWidget(parent), acts_(acts) {
    auto *layout = new QVBoxLayout(this);
    auto *top = new QHBoxLayout();
    channel_ = new QLabel(this);
    channel_->setObjectName("channel");
    auto *reclaim = new QPushButton("Reclaim", this);
    reclaim->setObjectName("reclaim");
    reclaim->hide();
    auto *output = new QLabel(this);
    QPointer<QLabel> out(output);
    connect(reclaim, &QPushButton::clicked, this, [this, out] { run(out, [this] { return acts_.reclaim(); }); });
    reclaim_ = reclaim;
    top->addWidget(channel_);
    top->addWidget(reclaim);
    top->addWidget(output);
    layout->addLayout(top);
    units_ = new QVBoxLayout();
    layout->addLayout(units_);
    layout->addStretch();
}

void Window::run(QPointer<QLabel> output, std::function<std::string()> act) {
    std::thread([output, act] {
        std::string line;
        try {
            line = act();
        } catch (const std::exception &e) {
            line = said(e);
        }
        QMetaObject::invokeMethod(qApp, [output, line] {
            if (output) {
                output->setText(QString::fromStdString(line));
            }
        });
    }).detach();
}

void Window::row(QVBoxLayout *into, const QString &label, const QString &name,
                 std::function<std::string(const std::string &)> act, bool payload) {
    auto *line = new QHBoxLayout();
    auto *button = new QPushButton(label, this);
    button->setObjectName(name);
    QLineEdit *input = nullptr;
    if (payload) {
        input = new QLineEdit(this);
        input->setPlaceholderText("payload");
    }
    auto *output = new QLabel(this);
    QPointer<QLabel> out(output);
    QPointer<QLineEdit> in(input);
    connect(button, &QPushButton::clicked, this, [this, out, in, act] {
        std::string text = in ? in->text().toStdString() : "";
        run(out, [act, text] { return act(text); });
    });
    line->addWidget(button);
    if (input) {
        line->addWidget(input);
    }
    line->addWidget(output);
    into->addLayout(line);
}

QWidget *Window::card(const v1::UnitRecord &unit) {
    const std::string id = unit.declared().identity();
    const QString q = QString::fromStdString(id);
    auto *w = new QWidget(this);
    auto *layout = new QVBoxLayout(w);
    auto *title = new QLabel("<b>" + q.toHtmlEscaped() + "</b>", w);
    layout->addWidget(title);
    auto *state = new QLabel(w);
    state->setObjectName("state:" + q);
    layout->addWidget(state);
    const auto &a = unit.addressed();
    for (const auto &type : a.commands()) {
        row(layout, "command " + QString::fromStdString(type), "command:" + q + ":" + QString::fromStdString(type),
            [this, id, type](const std::string &p) { return acts_.command(id, type, p); }, true);
    }
    for (const auto &type : a.queries()) {
        row(layout, "ask " + QString::fromStdString(type), "ask:" + q + ":" + QString::fromStdString(type),
            [this, id, type](const std::string &p) { return acts_.ask(id, type, p); }, true);
    }
    for (const auto &stream : a.streams()) {
        const QString s = QString::fromStdString(stream);
        layout->addWidget(new QLabel(s, w));
        row(layout, "start", "start:" + q + ":" + s, [this, id, stream](const std::string &) { return acts_.start(id, stream); }, false);
        row(layout, "stop", "stop:" + q + ":" + s, [this, id, stream](const std::string &) { return acts_.stop(id, stream); }, false);
        auto *output = new QLabel(w);
        QPointer<QLabel> out(output);
        row(layout, "watch", "watch:" + q + ":" + s,
            [this, id, stream, out](const std::string &) {
                return acts_.watch(id, stream, [out](const std::string &frame) {
                    QMetaObject::invokeMethod(qApp, [out, frame] {
                        if (out) {
                            out->setText(QString::fromStdString(frame));
                        }
                    });
                });
            },
            false);
        layout->addWidget(output);
    }
    if (a.commands().empty() && a.queries().empty() && a.streams().empty()) {
        auto *nothing = new QLabel(QString::fromStdString(unit.declared().kind()) + ": nothing this channel may address", w);
        nothing->setObjectName("nothing:" + q);
        layout->addWidget(nothing);
    }
    return w;
}

void Window::draw(const Picture &picture) {
    if (const auto *c = picture.channel()) {
        const auto &d = c->declared();
        const auto &o = c->observed();
        std::string what = o.suspended()
                               ? "suspended, " + o.grade() + (o.by().empty() ? "" : " — " + o.by() + " prevails") +
                                     (o.reason().empty() ? "" : " (" + o.reason() + ")")
                               : "active";
        channel_->setText(QString::fromStdString(d.name() + " · " + d.projection() + " on " + d.address_class() +
                                                 ", " + d.clients() + " · " + what));
        // Taking control back is offered only where it can be asked: on a channel bound as a local socket.
        reclaim_->setVisible(d.address_class() == "local-socket" && o.suspended());
    }
    std::set<std::string> seen;
    for (const auto *unit : picture.units()) {
        const std::string id = unit->declared().identity();
        seen.insert(id);
        const std::string shape = unit->addressed().SerializeAsString();
        auto it = cards_.find(id);
        if (it == cards_.end() || it->second.shape != shape) {
            QWidget *w = card(*unit);
            if (it != cards_.end()) {
                units_->replaceWidget(it->second.widget, w);
                it->second.widget->deleteLater();
            } else {
                units_->addWidget(w);
            }
            cards_[id] = Card{w, w->findChild<QLabel *>("state:" + QString::fromStdString(id)), shape};
        }
        const auto &o = unit->observed();
        std::string state = o.state().empty() ? "unknown" : o.state();
        if (o.has_condition() && !o.condition().line().empty()) {
            state += " · " + o.condition().line();
        }
        cards_[id].state->setText(QString::fromStdString(state));
    }
    for (auto it = cards_.begin(); it != cards_.end();) {
        if (!seen.count(it->first)) {
            it->second.widget->deleteLater();
            it = cards_.erase(it);
        } else {
            ++it;
        }
    }
}

} // namespace panel
